import Foundation
import AppKit
import Darwin

/// Обёртка над private MediaRemote + fallback через osascript/JXA.
///
/// С macOS 15.4 mediaremoted проверяет entitlements вызывающего процесса:
/// `MRMediaRemoteGetNowPlayingInfo` из обычного app часто отдаёт пусто,
/// при этом `MRMediaRemoteSendCommand` (медиа-клавиши) всё ещё работает.
/// Читаем метаданные через `/usr/bin/osascript` (системный бинарь с доступом).
final class MediaRemoteController {
    var onUpdate: ((NowPlayingInfo) -> Void)?

    private var handle: UnsafeMutableRawPointer?
    private var timer: Timer?
    private var available = false
    private var notificationTokens: [NSObjectProtocol] = []
    private var jxaInFlight = false
    /// Пока JXA летел, пришёл ещё refresh — после ответа перезапустим.
    private var jxaNeedsRerun = false

    private typealias GetNowPlayingInfoFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (NSDictionary?) -> Void
    ) -> Void

    private typealias GetIsPlayingFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (UInt8) -> Void
    ) -> Void

    private typealias SendCommandFn = @convention(c) (UInt32, NSDictionary?) -> Bool

    private typealias GetApplicationPIDFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Int32) -> Void
    ) -> Void

    private typealias RegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias SetElapsedTimeFn = @convention(c) (Double) -> Void

    private var getNowPlayingInfo: GetNowPlayingInfoFn?
    private var getIsPlaying: GetIsPlayingFn?
    private var sendCommand: SendCommandFn?
    private var getApplicationPID: GetApplicationPIDFn?
    private var registerNotifications: RegisterNotificationsFn?
    private var setElapsedTime: SetElapsedTimeFn?

    private var keyTitle = "title"
    private var keyArtist = "artist"
    private var keyAlbum = "album"
    private var keyDuration = "duration"
    private var keyElapsed = "elapsedTime"
    private var keyArtwork = "artworkData"
    private var optionPlaybackPosition = "kMRMediaRemoteOptionPlaybackPosition"

    private enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
        /// Перемотка на абсолютную позицию (секунды в options).
        case changePlaybackPosition = 46
    }

    private var lastInfo = NowPlayingInfo.empty
    private var refreshGeneration = 0
    /// После пустого MR (типично 15.4+) читаем метаданные через JXA, artwork — ещё пробуем из MR.
    private var preferJXA = false
    /// Пока пользователь тянет scrubber — не затираем elapsed с polling.
    private var scrubHoldUntil: Date?
    /// Кэш обложки: ключ трека → bytes (JXA часто без artwork).
    private var artworkCache: [String: Data] = [:]
    private var lastArtworkKey: String = ""
    private var artworkFetchInFlight = false

    func start() {
        loadFramework()
        NSLog("[MacIsland][MR] dlopen available=%d getInfo=%d getPlaying=%d send=%d register=%d",
              available ? 1 : 0,
              getNowPlayingInfo != nil ? 1 : 0,
              getIsPlaying != nil ? 1 : 0,
              sendCommand != nil ? 1 : 0,
              registerNotifications != nil ? 1 : 0)
        NSLog("[MacIsland][MR] keys title=%@ artist=%@ duration=%@",
              keyTitle as NSString, keyArtist as NSString, keyDuration as NSString)

        if available {
            registerForNotifications()
        }

        refresh()
        // Поллинг: нотификации + JXA fallback.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        if let handle {
            dlclose(handle)
            self.handle = nil
        }
    }

    func togglePlayPause() { send(.togglePlayPause) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }

    func seek(to fraction: Double) {
        let f = min(max(fraction, 0), 1)
        let duration = lastInfo.duration
        guard duration > 0, lastInfo.isAvailable else { return }
        let time = f * duration

        // Оптимистично двигаем elapsed, чтобы UI не прыгал назад.
        var optimistic = lastInfo
        optimistic.elapsed = time
        lastInfo = optimistic
        scrubHoldUntil = Date().addingTimeInterval(0.8)
        if Thread.isMainThread {
            onUpdate?(optimistic)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(optimistic)
            }
        }

        var sent = false
        if let setElapsedTime {
            setElapsedTime(time)
            sent = true
            NSLog("[MacIsland][MR] seek SetElapsedTime=%.2f", time)
        }

        if let sendCommand {
            let options: NSDictionary = [optionPlaybackPosition: time]
            let ok = sendCommand(Command.changePlaybackPosition.rawValue, options)
            sent = sent || ok
            NSLog("[MacIsland][MR] seek ChangePlaybackPosition=%.2f ok=%d", time, ok ? 1 : 0)

            // На всякий случай — другие известные ID, если 46 не принят.
            if !ok {
                for alt: UInt32 in [44, 47] {
                    let altOk = sendCommand(alt, options)
                    if altOk {
                        sent = true
                        NSLog("[MacIsland][MR] seek altCmd=%u ok=1", alt)
                        break
                    }
                }
            }
        }

        if !sent {
            NSLog("[MacIsland][MR] seek: нет доступного API")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Framework

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(path, RTLD_LAZY)
        guard let handle else {
            let err = String(cString: dlerror())
            NSLog("[MacIsland][MR] dlopen FAILED: %@", err as NSString)
            available = false
            return
        }

        getNowPlayingInfo = castSymbol(handle, "MRMediaRemoteGetNowPlayingInfo")
        getIsPlaying = castSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        sendCommand = castSymbol(handle, "MRMediaRemoteSendCommand")
        getApplicationPID = castSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationPID")
        registerNotifications = castSymbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        setElapsedTime = castSymbol(handle, "MRMediaRemoteSetElapsedTime")

        if let v = loadCFStringConstant(handle, "kMRMediaRemoteNowPlayingInfoTitle") { keyTitle = v }
        if let v = loadCFStringConstant(handle, "kMRMediaRemoteNowPlayingInfoArtist") { keyArtist = v }
        if let v = loadCFStringConstant(handle, "kMRMediaRemoteNowPlayingInfoAlbum") { keyAlbum = v }
        if let v = loadCFStringConstant(handle, "kMRMediaRemoteNowPlayingInfoDuration") { keyDuration = v }
        if let v = loadCFStringConstant(handle, "kMRMediaRemoteNowPlayingInfoElapsedTime") { keyElapsed = v }
        if let v = loadCFStringConstant(handle, "kMRMediaRemoteNowPlayingInfoArtworkData") { keyArtwork = v }
        if let v = loadCFStringConstant(handle, "kMRMediaRemoteOptionPlaybackPosition") {
            optionPlaybackPosition = v
        }

        available = getNowPlayingInfo != nil || sendCommand != nil
        NSLog("[MacIsland][MR] setElapsed=%d optionPos=%@ artworkKey=%@",
              setElapsedTime != nil ? 1 : 0,
              optionPlaybackPosition as NSString,
              keyArtwork as NSString)
    }

    private func castSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private func loadCFStringConstant(_ handle: UnsafeMutableRawPointer, _ name: String) -> String? {
        guard let sym = dlsym(handle, name) else { return nil }
        let ptrValue = UnsafeRawPointer(sym).load(as: UInt.self)
        guard ptrValue != 0, ptrValue > 0x1000 else { return nil }
        let cf = Unmanaged<CFString>.fromOpaque(UnsafeRawPointer(bitPattern: ptrValue)!).takeUnretainedValue()
        let str = cf as String
        return str.isEmpty ? nil : str
    }

    private func registerForNotifications() {
        // Важно: main runloop / main queue — иначе LSUIElement иногда не получает колбэки.
        registerNotifications?(DispatchQueue.main)

        var resolvedNames = Set([
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "MRMediaRemoteNowPlayingInfoDidChangeNotification",
            "MRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "MRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ])

        if let handle {
            for symbol in [
                "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            ] {
                if let v = loadCFStringConstant(handle, symbol) {
                    resolvedNames.insert(v)
                }
            }
        }

        for name in resolvedNames {
            let token = NotificationCenter.default.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            notificationTokens.append(token)
        }
    }

    private func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Refresh

    private func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration

        if preferJXA || getNowPlayingInfo == nil {
            refreshViaJXA(generation: generation)
            // Отдельный MR-вызов только ради artwork — title из JXA не затираем.
            fetchArtworkFromMRIfPossible()
        } else if let getNowPlayingInfo {
            refreshViaMediaRemote(generation: generation, getNowPlayingInfo: getNowPlayingInfo)
        }
    }

    /// MR GetNowPlayingInfo только для bytes обложки. Не трогаем title/artist из JXA.
    private func fetchArtworkFromMRIfPossible() {
        guard let getNowPlayingInfo else {
            NSLog("[MacIsland][Art] MR GetNowPlayingInfo unavailable")
            return
        }
        getNowPlayingInfo(DispatchQueue.main) { [weak self] dict in
            guard let self else { return }
            guard let dict else {
                NSLog("[MacIsland][Art] MR artwork callback dict=nil")
                return
            }
            let keyList = (dict.allKeys as [Any]).map { "\($0)" }.joined(separator: ",")
            NSLog("[MacIsland][Art] MR artwork dict count=%d keys=%@", dict.count, keyList as NSString)

            guard dict.count > 0 else { return }

            // Только обложка. Даже если в dict есть title — не emit'им MR-метаданные поверх JXA.
            guard let data = self.decodeArtworkData(from: dict) else {
                NSLog("[MacIsland][Art] MR artwork decode miss")
                return
            }
            NSLog("[MacIsland][Art] MR artwork bytes=%d → merge into lastInfo", data.count)
            guard self.lastInfo.isAvailable else { return }
            self.storeArtwork(data, for: self.lastInfo)
            var patched = self.lastInfo
            if patched.artworkData != data {
                patched.artworkData = data
                self.emit(patched)
            }
        }
    }

    private func refreshViaMediaRemote(generation: Int, getNowPlayingInfo: GetNowPlayingInfoFn) {
        let queue = DispatchQueue.main
        let group = DispatchGroup()

        var playing = false
        var appName = ""
        var appBundle = ""
        var dict: NSDictionary?
        var playingAnswered = false
        var infoAnswered = false

        group.enter()
        if let getIsPlaying {
            getIsPlaying(queue) { value in
                playing = value != 0
                playingAnswered = true
                group.leave()
            }
        } else {
            group.leave()
        }

        group.enter()
        if let getApplicationPID {
            getApplicationPID(queue) { pid in
                if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                    appName = app.localizedName ?? ""
                    appBundle = app.bundleIdentifier ?? ""
                }
                group.leave()
            }
        } else {
            group.leave()
        }

        group.enter()
        getNowPlayingInfo(queue) { info in
            dict = info
            infoAnswered = true
            group.leave()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, generation == self.refreshGeneration else { return }
            if !infoAnswered || (!playingAnswered && self.getIsPlaying != nil) {
                NSLog("[MacIsland][MR] timeout waiting callbacks info=%d playing=%d → JXA",
                      infoAnswered ? 1 : 0, playingAnswered ? 1 : 0)
                self.refreshViaJXA(generation: generation)
            }
        }

        group.notify(queue: queue) { [weak self] in
            guard let self, generation == self.refreshGeneration else { return }
            let keys = (dict?.allKeys as? [Any])?.map { "\($0)" } ?? []
            let titleProbe = self.stringValue(
                dict ?? [:],
                keys: [self.keyTitle, "kMRMediaRemoteNowPlayingInfoTitle", "Title", "title"]
            )
            NSLog("[MacIsland][MR] dict count=%d keys=%@ title='%@' playing=%d app='%@'",
                  dict?.count ?? -1,
                  keys.joined(separator: ",") as NSString,
                  titleProbe as NSString,
                  playing ? 1 : 0,
                  appName as NSString)

            if let dict, dict.count > 0,
               let info = self.parseMRDict(dict, isPlaying: playing, appName: appName, appBundle: appBundle) {
                self.emit(info)
            } else {
                NSLog("[MacIsland][MR] empty dict → prefer JXA fallback")
                self.preferJXA = true
                self.refreshViaJXA(generation: generation)
            }
        }
    }

    private func parseMRDict(
        _ dict: NSDictionary,
        isPlaying: Bool,
        appName: String,
        appBundle: String
    ) -> NowPlayingInfo? {
        let title = stringValue(dict, keys: [keyTitle, "kMRMediaRemoteNowPlayingInfoTitle", "Title", "title"])
        let artist = stringValue(dict, keys: [keyArtist, "kMRMediaRemoteNowPlayingInfoArtist", "Artist", "artist"])
        let album = stringValue(dict, keys: [keyAlbum, "kMRMediaRemoteNowPlayingInfoAlbum", "Album", "album"])
        let duration = timeValue(dict, keys: [keyDuration, "kMRMediaRemoteNowPlayingInfoDuration", "Duration", "duration"])
        let elapsed = timeValue(dict, keys: [keyElapsed, "kMRMediaRemoteNowPlayingInfoElapsedTime", "ElapsedTime", "elapsedTime"])

        let artworkData = decodeArtworkData(from: dict)

        let hasMeta = !title.isEmpty || !artist.isEmpty || artworkData != nil
        if !hasMeta && !(isPlaying && !appName.isEmpty) {
            return nil
        }

        let resolvedTitle = title.isEmpty ? (isPlaying ? "Сейчас играет" : "Без названия") : title
        let info = NowPlayingInfo(
            title: resolvedTitle,
            artist: artist,
            album: album,
            artworkData: artworkData,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying,
            appName: appName,
            appBundleIdentifier: appBundle,
            isAvailable: true
        )
        if let artworkData {
            storeArtwork(artworkData, for: info)
        }
        return info
    }

    // MARK: - Artwork decode

    /// Перебор известных ключей + nested dict. Логи `[MacIsland][Art]`.
    private func decodeArtworkData(from dict: NSDictionary) -> Data? {
        let keys = [
            keyArtwork,
            "kMRMediaRemoteNowPlayingInfoArtworkData",
            "ArtworkData",
            "artworkData",
            "artwork",
            "MRMediaRemoteNowPlayingInfoArtworkData",
        ]
        for key in keys {
            guard let value = dict[key] else { continue }
            let typeName = String(describing: type(of: value))
            if let data = dataFromArtworkValue(value) {
                NSLog("[MacIsland][Art] key='%@' type=%@ bytes=%d ok", key as NSString, typeName as NSString, data.count)
                return data
            }
            NSLog("[MacIsland][Art] key='%@' type=%@ decode FAIL", key as NSString, typeName as NSString)
        }

        for key in keys {
            guard let nested = dict[key] as? NSDictionary else { continue }
            for nestedKey in ["data", "artworkData", "ArtworkData", "imageData"] {
                if let value = nested[nestedKey], let data = dataFromArtworkValue(value) {
                    NSLog("[MacIsland][Art] nested %@.%@ bytes=%d ok", key as NSString, nestedKey as NSString, data.count)
                    return data
                }
            }
        }
        return nil
    }

    private func dataFromArtworkValue(_ value: Any) -> Data? {
        if value is NSNull { return nil }
        if let data = value as? Data, !data.isEmpty {
            return data
        }
        if let data = value as? NSData, data.length > 0 {
            return data as Data
        }
        if let image = value as? NSImage, let tiff = image.tiffRepresentation {
            return tiff
        }
        if let dict = value as? NSDictionary {
            for nestedKey in ["data", "artworkData", "ArtworkData", "imageData"] {
                if let nested = dict[nestedKey], let data = dataFromArtworkValue(nested) {
                    return data
                }
            }
        }
        // CFData только если это реально CFData — иначе CFGetTypeID может увести в crash.
        if type(of: value) is AnyClass {
            let obj = value as AnyObject
            let typeID = CFGetTypeID(obj as CFTypeRef)
            if typeID == CFDataGetTypeID() {
                let data = (obj as! CFData) as Data
                return data.isEmpty ? nil : data
            }
        }
        return nil
    }

    private func trackKey(title: String, artist: String, bundle: String) -> String {
        "\(bundle)|\(artist)|\(title)"
    }

    private func storeArtwork(_ data: Data, for info: NowPlayingInfo) {
        let key = trackKey(title: info.title, artist: info.artist, bundle: info.appBundleIdentifier)
        artworkCache[key] = data
        lastArtworkKey = key
    }

    private func cachedArtworkData(for info: NowPlayingInfo) -> Data? {
        let key = trackKey(title: info.title, artist: info.artist, bundle: info.appBundleIdentifier)
        if let data = artworkCache[key] { return data }
        if info.title == lastInfo.title,
           info.artist == lastInfo.artist,
           !lastArtworkKey.isEmpty {
            return artworkCache[lastArtworkKey] ?? lastInfo.artworkData
        }
        return nil
    }

    // MARK: - JXA fallback

    private func refreshViaJXA(generation: Int) {
        // Если уже летит запрос — пометим, что нужен ещё один после него.
        if jxaInFlight {
            jxaNeedsRerun = true
            return
        }
        jxaInFlight = true
        jxaNeedsRerun = false

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.runJXANowPlaying()
            DispatchQueue.main.async {
                guard let self else { return }
                self.jxaInFlight = false

                let rerun = self.jxaNeedsRerun || generation != self.refreshGeneration
                self.jxaNeedsRerun = false

                switch result {
                case .success(let info):
                    NSLog("[MacIsland][JXA] ok title='%@' artist='%@' playing=%d app='%@' available=%d artBytes=%d",
                          info.title as NSString,
                          info.artist as NSString,
                          info.isPlaying ? 1 : 0,
                          info.appName as NSString,
                          info.isAvailable ? 1 : 0,
                          info.artworkData?.count ?? 0)
                    if info.isAvailable {
                        var merged = info
                        // Обложку подмешиваем, но метаданные из JXA — источник истины.
                        if !merged.hasArtwork {
                            merged.artworkData = self.cachedArtworkData(for: info)
                        }
                        if let data = merged.artworkData {
                            self.storeArtwork(data, for: merged)
                        }
                        self.emit(merged)
                        if !merged.hasArtwork {
                            self.fetchPlayerArtworkFallback(for: merged)
                        }
                    } else {
                        NSLog("[MacIsland][JXA] → emit empty")
                        self.emit(.empty)
                    }
                case .failure(let err):
                    NSLog("[MacIsland][JXA] fail: %@", err as NSString)
                    // Не сносим рабочий Now Playing из‑за разового сбоя osascript.
                    if !self.lastInfo.isAvailable {
                        self.emit(.empty)
                    }
                }

                // Пока JXA работал, generation ушёл вперёд — догоняем актуальный snapshot.
                if rerun {
                    self.refreshViaJXA(generation: self.refreshGeneration)
                }
            }
        }
    }

    private enum JXAResult {
        case success(NowPlayingInfo)
        case failure(String)
    }

    /// Метаданные через JXA (как до artwork-регресса). Обложку — файлом, без base64 в JSON.
    private static func runJXANowPlaying() -> JXAResult {
        // Тот же проверенный путь к .framework/ (не к бинарю внутри).
        let script = """
        function run() {
          const MediaRemote = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
          MediaRemote.load;
          const MRNowPlayingRequest = $.NSClassFromString('MRNowPlayingRequest');
          if (!MRNowPlayingRequest) return JSON.stringify({ok:false, reason:'no class'});

          let isPlaying = false;
          try { isPlaying = !!MRNowPlayingRequest.localIsPlaying; } catch (e) {}

          let appName = '';
          let bundleId = '';
          try {
            const client = MRNowPlayingRequest.localNowPlayingPlayerPath.client;
            appName = client.displayName.js || '';
            bundleId = client.bundleIdentifier.js || '';
          } catch (e) {}

          let title = '', artist = '', album = '';
          let duration = 0, elapsed = 0;
          let keys = [];
          let artNote = 'none';
          let artPath = '';
          try {
            const item = MRNowPlayingRequest.localNowPlayingItem;
            if (item && !(item.isNil && item.isNil())) {
              const infoDict = item.nowPlayingInfo;
              if (infoDict && !(infoDict.isNil && infoDict.isNil())) {
                try { keys = Object.keys(infoDict.js || {}); } catch (e) {}
                function val(k) {
                  try {
                    const v = infoDict.valueForKey(k);
                    if (!v || (v.isNil && v.isNil())) return null;
                    return v.js;
                  } catch (e) { return null; }
                }
                title = val('kMRMediaRemoteNowPlayingInfoTitle') || val('title') || '';
                artist = val('kMRMediaRemoteNowPlayingInfoArtist') || val('artist') || '';
                album = val('kMRMediaRemoteNowPlayingInfoAlbum') || val('album') || '';
                duration = Number(val('kMRMediaRemoteNowPlayingInfoDuration') || val('duration') || 0) || 0;
                elapsed = Number(val('kMRMediaRemoteNowPlayingInfoElapsedTime') || val('elapsedTime') || 0) || 0;

                // Обложка опционально: пишем bytes в файл, в JSON только путь.
                const artKeys = [
                  'kMRMediaRemoteNowPlayingInfoArtworkData',
                  'artworkData',
                  'ArtworkData'
                ];
                for (let i = 0; i < artKeys.length; i++) {
                  try {
                    const art = infoDict.valueForKey(artKeys[i]);
                    if (!art || (art.isNil && art.isNil())) { artNote = artKeys[i] + '=nil'; continue; }
                    let len = -1;
                    try { len = Number(art.length); } catch (e) {}
                    const path = '/tmp/macisland-jxa-art.bin';
                    try {
                      if (art.writeToFileAtomically(path, true)) {
                        artPath = path;
                        artNote = artKeys[i] + '=file len:' + len;
                        break;
                      }
                      artNote = artKeys[i] + '=writeFalse len:' + len;
                    } catch (e) {
                      artNote = artKeys[i] + '=fileerr:' + e;
                    }
                  } catch (e) {
                    artNote = artKeys[i] + '=ex:' + e;
                  }
                }
              }
            } else {
              artNote = 'no_item';
            }
          } catch (e) {
            return JSON.stringify({ok:false, reason: String(e)});
          }

          return JSON.stringify({
            ok: true,
            isPlaying: isPlaying,
            appName: appName,
            bundleId: bundleId,
            title: title || '',
            artist: artist || '',
            album: album || '',
            duration: duration,
            elapsed: elapsed,
            keys: keys,
            artPath: artPath,
            artNote: artNote
          });
        }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure("spawn: \(error.localizedDescription)")
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            return .failure("exit \(process.terminationStatus) \(errText)")
        }

        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let jsonData = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return .failure("bad json \(errText)")
        }

        if let keys = obj["keys"] as? [String] {
            NSLog("[MacIsland][JXA] dict keys=%@", keys.joined(separator: ",") as NSString)
        }
        if let artNote = obj["artNote"] as? String {
            NSLog("[MacIsland][Art] JXA note=%@", artNote as NSString)
        }

        guard jsonBool(obj["ok"]) else {
            return .failure((obj["reason"] as? String) ?? "ok=false")
        }

        let title = (obj["title"] as? String) ?? ""
        let artist = (obj["artist"] as? String) ?? ""
        let album = (obj["album"] as? String) ?? ""
        let appName = (obj["appName"] as? String) ?? ""
        let bundleId = (obj["bundleId"] as? String) ?? ""
        let isPlaying = jsonBool(obj["isPlaying"])
        let duration = jsonDouble(obj["duration"])
        let elapsed = jsonDouble(obj["elapsed"])

        var artworkData: Data?
        if let artPath = obj["artPath"] as? String, !artPath.isEmpty {
            let fileURL = URL(fileURLWithPath: artPath)
            if let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty {
                artworkData = fileData
                NSLog("[MacIsland][Art] JXA file decode bytes=%d", fileData.count)
            }
            try? FileManager.default.removeItem(at: fileURL)
        }

        let hasMeta = !title.isEmpty || !artist.isEmpty || !appName.isEmpty || artworkData != nil
        if !hasMeta && !isPlaying {
            NSLog("[MacIsland][JXA] → empty (no meta, not playing)")
            return .success(.empty)
        }

        let info = NowPlayingInfo(
            title: title.isEmpty ? (isPlaying ? "Сейчас играет" : "Без названия") : title,
            artist: artist,
            album: album,
            artworkData: artworkData,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying,
            appName: appName,
            appBundleIdentifier: bundleId,
            isAvailable: true
        )
        return .success(info)
    }

    private static func jsonBool(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let i = value as? Int { return i != 0 }
        return false
    }

    private static func jsonDouble(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        return 0
    }

    /// Music.app / Spotify — когда MR не отдаёт ArtworkData.
    private func fetchPlayerArtworkFallback(for info: NowPlayingInfo) {
        guard !artworkFetchInFlight else { return }
        let bundle = info.appBundleIdentifier.lowercased()
        let isMusic = bundle.contains("com.apple.music") || bundle.contains("com.apple.itunes")
        let isSpotify = bundle.contains("spotify")
        guard isMusic || isSpotify else {
            NSLog("[MacIsland][Art] no player fallback for bundle=%@", info.appBundleIdentifier as NSString)
            return
        }

        artworkFetchInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data: Data?
            if isMusic {
                data = Self.fetchMusicAppArtworkData()
            } else {
                data = Self.fetchSpotifyArtworkData()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.artworkFetchInFlight = false
                guard let data, !data.isEmpty else {
                    NSLog("[MacIsland][Art] player fallback empty bundle=%@", info.appBundleIdentifier as NSString)
                    return
                }
                guard self.lastInfo.isAvailable,
                      self.lastInfo.title == info.title,
                      self.lastInfo.appBundleIdentifier == info.appBundleIdentifier else {
                    NSLog("[MacIsland][Art] player fallback stale, skip")
                    return
                }
                NSLog("[MacIsland][Art] player fallback ok bytes=%d", data.count)
                var patched = self.lastInfo
                patched.artworkData = data
                self.storeArtwork(data, for: patched)
                self.emit(patched)
            }
        }
    }

    private static func fetchMusicAppArtworkData() -> Data? {
        let path = NSTemporaryDirectory() + "macisland-music-art-\(UUID().uuidString).bin"
        let wrapped = """
        set p to "\(path)"
        try
          tell application "Music"
            if player state is stopped then return "empty"
            set artCount to count of artworks of current track
            if artCount < 1 then return "empty"
            set d to raw data of artwork 1 of current track
            set f to open for access POSIX file p with write permission
            set eof of f to 0
            write d to f
            close access f
            return "ok"
          end tell
        on error
          try
            close access POSIX file p
          end try
          return "err"
        end try
        """
        guard let result = runAppleScriptString(wrapped)?.trimmingCharacters(in: .whitespacesAndNewlines),
              result == "ok" else {
            try? FileManager.default.removeItem(atPath: path)
            return nil
        }
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    private static func fetchSpotifyArtworkData() -> Data? {
        let urlScript = """
        try
          tell application "Spotify"
            if player state is stopped then return ""
            return artwork url of current track as text
          end tell
        on error
          return ""
        end try
        """
        guard let urlString = runAppleScriptString(urlScript)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func runAppleScriptString(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func emit(_ info: NowPlayingInfo) {
        var outgoing = info
        if let hold = scrubHoldUntil, Date() < hold, lastInfo.isAvailable, outgoing.isAvailable {
            let sameTrack =
                outgoing.title == lastInfo.title
                && outgoing.appBundleIdentifier == lastInfo.appBundleIdentifier
            if sameTrack {
                outgoing.elapsed = lastInfo.elapsed
            } else {
                scrubHoldUntil = nil
            }
        } else if scrubHoldUntil != nil, let hold = scrubHoldUntil, Date() >= hold {
            scrubHoldUntil = nil
        }

        if outgoing.isAvailable, !outgoing.hasArtwork {
            outgoing.artworkData = cachedArtworkData(for: outgoing)
        }
        if let data = outgoing.artworkData {
            storeArtwork(data, for: outgoing)
        } else if outgoing.isAvailable,
                  (outgoing.title != lastInfo.title || outgoing.artist != lastInfo.artist) {
            lastArtworkKey = ""
        }

        NSLog("[MacIsland][Art] emit title='%@' artBytes=%d playing=%d",
              outgoing.title as NSString,
              outgoing.artworkData?.count ?? 0,
              outgoing.isPlaying ? 1 : 0)

        lastInfo = outgoing
        if Thread.isMainThread {
            onUpdate?(outgoing)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(outgoing)
            }
        }
    }

    private func stringValue(_ dict: NSDictionary, keys: [String]) -> String {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let s = dict[key] as? NSString { return s as String }
        }
        return ""
    }

    private func timeValue(_ dict: NSDictionary, keys: [String]) -> TimeInterval {
        for key in keys {
            if let n = dict[key] as? TimeInterval { return n }
            if let n = dict[key] as? Double { return n }
            if let n = dict[key] as? NSNumber { return n.doubleValue }
        }
        return 0
    }
}

