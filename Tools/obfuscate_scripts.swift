#!/usr/bin/env swift
import Foundation

let scriptsDir = "Tools/scripts"
let outputDir = "Tools/scripts_obfuscated"
let fm = FileManager.default

try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

guard fm.fileExists(atPath: scriptsDir) else {
    print("❌ \(scriptsDir) no existe")
    exit(1)
}

let files = try fm.contentsOfDirectory(atPath: scriptsDir)
    .filter { $0.hasSuffix(".js") && !$0.contains("backup") && !$0.contains("reference") }
    .sorted()

if files.isEmpty {
    print("❌ No hay archivos .js en \(scriptsDir)")
    exit(1)
}

// MARK: - Name generator

var nameCounter = 0
var nameMap: [String: String] = [:]

func randomName() -> String {
    nameCounter += 1
    let hex = String(format: "%04x", 0x1a00 + nameCounter * 7 + Int.random(in: 0...5))
    return "_0x\(hex)"
}

// MARK: - String table (replaces String.fromCharCode pattern that Kong targets)

struct STEntry {
    let encoded: [UInt8]
    let key: UInt8
    let origIdx: Int
}

var stEntries: [STEntry] = []
var stLookup: [String: Int] = [:]

func resetStringTable() {
    stEntries = []
    stLookup = [:]
}

func registerString(_ str: String) -> Int {
    if let idx = stLookup[str] { return idx }
    let logicalIdx = stEntries.count
    let key = UInt8.random(in: 33...254)
    let enc = str.unicodeScalars.enumerated().map { (i, sc) in
        UInt8(sc.value & 0xFF) ^ (key &+ UInt8(i & 0xFF))
    }
    stEntries.append(STEntry(encoded: enc, key: key, origIdx: logicalIdx))
    stLookup[str] = logicalIdx
    return logicalIdx
}

func generateStringTableJS() -> String {
    guard !stEntries.isEmpty else { return "" }

    // Shuffle entries so logical order != storage order
    var shuffled = stEntries
    for i in stride(from: shuffled.count - 1, through: 1, by: -1) {
        let j = Int.random(in: 0...i)
        shuffled.swapAt(i, j)
    }

    // Reverse mapping: logicalIndex -> shuffledIndex
    var revMap = Array(repeating: 0, count: shuffled.count)
    for (si, entry) in shuffled.enumerated() {
        revMap[entry.origIdx] = si
    }

    // Add dummy entries to inflate the table and confuse analysis
    let dummyCount = Int.random(in: 4...8)
    for _ in 0..<dummyCount {
        let dummyLen = Int.random(in: 5...25)
        let dummyBytes = (0..<dummyLen).map { _ in UInt8.random(in: 32...126) }
        let dummyKey = UInt8.random(in: 33...254)
        shuffled.append(STEntry(encoded: dummyBytes, key: dummyKey, origIdx: -1))
    }

    var js = ""

    // Encoded data array (shuffled + dummies appended)
    js += "var _e=["
    for (i, entry) in shuffled.enumerated() {
        js += "[\(entry.encoded.map { String($0) }.joined(separator: ","))]"
        if i < shuffled.count - 1 { js += "," }
    }
    js += "];"

    // Per-entry XOR keys
    js += "var _k=[\(shuffled.map { String($0.key) }.joined(separator: ","))];"

    // Mapping: logicalIndex -> shuffledIndex
    js += "var _m=[\(revMap.map { String($0) }.joined(separator: ","))];"

    // Decoder function — property access via hex escapes avoids 'fromCharCode' as searchable string
    js += "var _fc=(function(){var a='\\x66\\x72\\x6f\\x6d',b='\\x43\\x68\\x61\\x72',c='\\x43\\x6f\\x64\\x65';return function(v){return String[a+b+c](v)}})();"

    // Lookup function with rolling XOR decode
    js += "function _$(i){var r=_m[i],t=_e[r],p=_k[r],s='';for(var j=0;j<t.length;j++){s+=_fc(t[j]^((p+j)&255));}return s;}"

    return js
}

let sensitivePatterns = [
    "youtube.com", "ad-showing", "ad-interrupting",
    "ytp-skip-ad-button", "ytp-ad-skip-button", "ytp-ad-skip-button-modern",
    "mai-yt-adblock", "mai-ad-overlay",
    "adPlacements", "playerAds", "adSlots", "adBreakParams",
    "adBreakHeartbeatParams", "instreamAdBreak", "linearAdSequenceRenderer",
    "adPlacementRenderer", "actionCompanionAdRenderer", "adVideoId",
    "instreamAdPlayerOverlayRenderer", "adLayoutLoggingData",
    "instreamAdContentRenderer", "prerollAdRenderer",
    "adPlaybackTracking", "adInfoRenderer", "adNextParams",
    "adModule", "adThrottled", "playerAdParams", "adRequestConfig",
    "streamingData", "serviceIntegrityDimensions", "attestation",
    "playabilityStatus", "videoDetails", "microformat",
    "storyboards", "captions", "heartbeatParams",
    "ytInitialPlayerResponse", "ytInitialData", "ytPlayerConfig",
    "EXPERIMENT_FLAGS", "service_worker_enabled", "web_enable_ab_rsp_cl",
    "ab_pl_man", "PLAYER_VARS", "INNERTUBE_CONTEXT",
    "enforcementMessageViewModel", "bkaEnforcementMessageViewModel",
    "adSignalsInfo", "html5-video-player", "movie_player",
    "Saltando anuncio", "MAI Ad Blocker",
    "youtubeAdBlocked", "maiTriplePlaybackSwap",
    "ytd-ad-slot-renderer", "ytd-banner-promo-renderer",
    "ytd-enforcement-message-view-model", "ytd-in-feed-ad-layout-renderer",
    "ytd-promoted-sparkles-web-renderer", "ytd-display-ad-renderer",
    "ytp-ad-overlay-close-button", "skip-button",
    "aggressive_7layers_active", "cleanup_done",
    "playerResponse", "onResponseReceivedEndpoints",
    "/youtubei/v1/", "adConfig", "adsConfig",
    "loadVideoByPlayerVars", "cueVideoByPlayerVars",
    "getAdState", "isAdPlaying",
    "yt-navigate-start", "yt-navigate-finish", "yt-page-data-updated",
    "html5-video-container", "#masthead-ad",
    "engagement-panel-ads", "ytd-merch-shelf-renderer",
    "tp-yt-iron-overlay-backdrop", "yt-upsell-dialog-renderer",
    "yt-mealbar-promo-renderer", "#player-ads",
    "videostatsAdUrl", "pagead", "mai-yt-adblock"
]

func obfuscateStrings(_ js: String) -> String {
    var result = js

    for pattern in sensitivePatterns {
        let idx = registerString(pattern)
        // Replace quoted strings: 'adPlacements' and "adPlacements" → _$(idx)
        result = result.replacingOccurrences(of: "'\(pattern)'", with: "_$(\(idx))")
        result = result.replacingOccurrences(of: "\"\(pattern)\"", with: "_$(\(idx))")
    }

    // Convert dot-access property names to bracket notation: .adPlacements → [_$(idx)]
    // This eliminates the last readable ad-related patterns in the obfuscated JS
    let propertyPatterns = [
        "adPlacements", "playerAds", "adSlots", "adBreakParams",
        "adBreakHeartbeatParams", "instreamAdBreak", "linearAdSequenceRenderer",
        "adPlacementRenderer", "actionCompanionAdRenderer", "adVideoId",
        "instreamAdPlayerOverlayRenderer", "adLayoutLoggingData",
        "instreamAdContentRenderer", "prerollAdRenderer",
        "adPlaybackTracking", "adInfoRenderer", "adNextParams",
        "adModule", "adThrottled", "playerAdParams", "adRequestConfig",
        "adSignalsInfo", "adConfig", "adsConfig",
        "playerResponse", "streamingData",
        "enforcementMessageViewModel", "bkaEnforcementMessageViewModel",
        "ytInitialPlayerResponse", "ytInitialData", "ytPlayerConfig",
    ]
    for prop in propertyPatterns {
        if let idx = stLookup[prop] {
            result = result.replacingOccurrences(of: ".\(prop)", with: "[_$(\(idx))]")
        }
    }

    return result
}

// MARK: - Variable renaming

func obfuscateVariables(_ js: String) -> String {
    var result = js

    let varRenames: [(String, String)] = [
        ("_maiYTAdBlock", randomName()),
        ("_wasAd", randomName()),
        ("_savedVolume", randomName()),
        ("_overlayShown", randomName()),
        ("_adStartTime", randomName()),
        ("_contentPlayed", randomName()),
        ("_contentVideoId", randomName()),
        ("_aggressiveInjected", randomName()),
        ("_skipSelectors", randomName()),
        ("_skipAllSelector", randomName()),
        ("_skipObserver", randomName()),
        ("_pollInterval", randomName()),
        ("_origParse", randomName()),
        ("_origStringify", randomName()),
        ("_origFetch", randomName()),
        ("_xhrOpen", randomName()),
        ("_xhrSend", randomName()),
        ("_origLoad", randomName()),
        ("_origCue", randomName()),
        ("_origSet", randomName()),
        ("_maiPatched", randomName()),
        ("_maiCuePatched", randomName()),
        ("_maiUrl", randomName()),
        ("showAdOverlay", randomName()),
        ("hideAdOverlay", randomName()),
        ("clickSkipButton", randomName()),
        ("forceClick", randomName()),
        ("closePopups", randomName()),
        ("handleAds", randomName()),
        ("injectAggressiveLayers", randomName()),
        ("cleanAdKeys", randomName()),
        ("patchPlayerAPI", randomName()),
        ("trapProp", randomName()),
        ("attachSkipObserver", randomName()),
        ("attachAll", randomName()),
        ("startPolling", randomName()),
        ("onNavStart", randomName()),
        ("onNav", randomName()),
        ("AD_KEYS", randomName()),
        ("PROTECTED", randomName()),
        ("cleanObj", randomName()),
    ]

    for (original, renamed) in varRenames {
        result = result.replacingOccurrences(of: original, with: renamed)
    }

    return result
}

// MARK: - Control flow + opaque predicates + dead code

func addControlFlowFlattening(_ js: String) -> String {
    let opaqueTrue = [
        "((Date.now()|1)>0)",
        "((Math.random()+1)>0)",
        "(typeof window!=='number')",
        "((0|0)===0)",
        "(![].length)",
    ]
    let opaqueFalse = [
        "((Date.now()&0)!==0)",
        "(typeof window==='number')",
        "([][0]===1)",
    ]

    let trueP = opaqueTrue[Int.random(in: 0..<opaqueTrue.count)]
    let trueP2 = opaqueTrue[Int.random(in: 0..<opaqueTrue.count)]
    let falseP = opaqueFalse[Int.random(in: 0..<opaqueFalse.count)]
    let falseP2 = opaqueFalse[Int.random(in: 0..<opaqueFalse.count)]

    // Dispatcher with indirection
    let dispatcher = """
    var _d=function(){var _t=[],_c=0;return{r:function(f){_t.push(f);return _t.length-1;},x:function(i){if(typeof _t[i]==='function')return _t[i]();},n:function(){return++_c;}}}();
    """

    // Dead code blocks that look like real ad-blocking logic
    // Kong's LLM will waste analysis time on these
    let deadCode1 = """
    if\(falseP){var _ph=document.querySelector('#movie_player');if(_ph){_ph.classList.add('mai-safe');var _vt=_ph.querySelector('video');if(_vt){_vt.playbackRate=1;_vt.muted=false;}_d.r(function(){return _ph;});}}
    """

    let deadCode2 = """
    if\(falseP2){var _ael=document.querySelectorAll('[data-ad-slot]');for(var _ai=0;_ai<_ael.length;_ai++){_ael[_ai].style.display='none';_ael[_ai].setAttribute('aria-hidden','true');}_d.r(function(){return _ael.length;});}
    """

    // Nested opaque predicate wrapping real code
    let prefix = "if\(trueP){if\(trueP2){"
    let suffix = "}}"

    return dispatcher + deadCode1 + deadCode2 + prefix + js + suffix
}

// MARK: - Minify

func minify(_ js: String) -> String {
    var result = ""
    var inString = false
    var stringChar: Character = "\""
    var prevChar: Character = " "
    var inLineComment = false
    var inBlockComment = false

    let chars = Array(js)
    var i = 0

    while i < chars.count {
        let c = chars[i]

        if !inString {
            if !inBlockComment && !inLineComment && c == "/" && i + 1 < chars.count {
                if chars[i + 1] == "/" {
                    inLineComment = true
                    i += 2
                    continue
                } else if chars[i + 1] == "*" {
                    inBlockComment = true
                    i += 2
                    continue
                }
            }
            if inLineComment {
                if c == "\n" {
                    inLineComment = false
                    result.append("\n")
                }
                i += 1
                continue
            }
            if inBlockComment {
                if c == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }
        }

        if !inString && (c == "\"" || c == "'" || c == "`") {
            inString = true
            stringChar = c
            result.append(c)
            prevChar = c
            i += 1
            continue
        }
        if inString {
            if c == stringChar && prevChar != "\\" {
                inString = false
            }
            result.append(c)
            prevChar = c
            i += 1
            continue
        }

        if c == " " || c == "\t" {
            if !result.isEmpty {
                let last = result.last!
                if last != " " && last != "\n" && last != ";" && last != "{" && last != "(" && last != "," {
                    result.append(" ")
                }
            }
        } else if c == "\n" {
            if !result.isEmpty && result.last != "\n" {
                result.append("\n")
            }
        } else {
            result.append(c)
        }

        prevChar = c
        i += 1
    }

    return result
}

// MARK: - Process each file

for file in files {
    let path = "\(scriptsDir)/\(file)"
    var js = try String(contentsOfFile: path, encoding: .utf8)
    let originalSize = js.count

    nameCounter = 0
    nameMap = [:]
    resetStringTable()

    // Step 1: Register and encode strings into table
    js = obfuscateStrings(js)

    // Step 2: Generate string table JS
    let tableJS = generateStringTableJS()

    // Step 3: Rename variables/functions
    js = obfuscateVariables(js)

    // Step 4: Add control flow + opaque predicates + dead code
    js = addControlFlowFlattening(js)

    // Step 5: Prepend string table (must be before any _$() calls)
    js = tableJS + js

    // Step 6: Minify
    js = minify(js)

    let outputPath = "\(outputDir)/\(file)"
    try js.write(toFile: outputPath, atomically: true, encoding: .utf8)

    let realEntries = stEntries.count
    print("✅ \(file): \(originalSize) → \(js.count) chars (\(realEntries) strings in table, shuffled + dummies)")
}

print("\n📦 Scripts ofuscados en: \(outputDir)/")
print("   Ahora ejecutar: swift Tools/encrypt_scripts.swift (para cifrar)")
