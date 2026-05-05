import AVFoundation

/// Text-to-speech wrapper around AVSpeechSynthesizer.
enum TTSService {
    private static let synth = AVSpeechSynthesizer()

    static func speak(_ text: String, language: String = "en-IN") {
        synth.stopSpeaking(at: .immediate)
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: language)
        utt.rate = 0.48
        utt.pitchMultiplier = 1.0
        synth.speak(utt)
    }

    static func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    static var isSpeaking: Bool { synth.isSpeaking }
}
