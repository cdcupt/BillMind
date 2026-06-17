import { useCallback, useEffect, useRef, useState } from "react";

// The Web Speech API isn't in the standard DOM lib types, so we describe the
// slice we use. Chrome/Edge expose `webkitSpeechRecognition`; Safari 14.1+ ships
// it too. Firefox has no support — callers gate on `supported`.
type SpeechRecognitionLike = {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  start: () => void;
  stop: () => void;
  abort: () => void;
  onresult: ((event: SpeechResultEvent) => void) | null;
  onerror: ((event: { error: string }) => void) | null;
  onend: (() => void) | null;
};

type SpeechResultEvent = {
  resultIndex: number;
  results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }>;
};

type SpeechRecognitionCtor = new () => SpeechRecognitionLike;

function speechRecognitionCtor(): SpeechRecognitionCtor | null {
  if (typeof window === "undefined") return null;
  const w = window as unknown as {
    SpeechRecognition?: SpeechRecognitionCtor;
    webkitSpeechRecognition?: SpeechRecognitionCtor;
  };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

export type VoiceCapture = {
  supported: boolean;
  isRecording: boolean;
  transcript: string;
  error: string | null;
  /** Begin dictation. `onFinish` fires once with the final transcript on stop. */
  start: (onFinish: (text: string) => void) => void;
  /** Stop listening — triggers `onFinish`. */
  stop: () => void;
};

export function useVoiceCapture(): VoiceCapture {
  const [isRecording, setIsRecording] = useState(false);
  const [transcript, setTranscript] = useState("");
  const [error, setError] = useState<string | null>(null);

  const recognitionRef = useRef<SpeechRecognitionLike | null>(null);
  const finishRef = useRef<((text: string) => void) | null>(null);
  const textRef = useRef(""); // latest full transcript — refs avoid stale closures

  const supported = speechRecognitionCtor() !== null;

  const stop = useCallback(() => {
    recognitionRef.current?.stop();
  }, []);

  const start = useCallback((onFinish: (text: string) => void) => {
    const Ctor = speechRecognitionCtor();
    if (!Ctor) {
      setError("Voice input isn't supported in this browser.");
      return;
    }

    const recognition = new Ctor();
    finishRef.current = onFinish;
    textRef.current = "";
    setTranscript("");
    setError(null);

    recognition.lang = navigator.language || "en-US";
    recognition.interimResults = true;
    recognition.continuous = true;

    recognition.onresult = (event) => {
      let finalText = "";
      let interim = "";
      for (let i = 0; i < event.results.length; i++) {
        const chunk = event.results[i][0].transcript;
        if (event.results[i].isFinal) finalText += chunk;
        else interim += chunk;
      }
      const full = (finalText + interim).trim();
      textRef.current = full;
      setTranscript(full);
    };

    recognition.onerror = (event) => {
      if (event.error === "aborted" || event.error === "no-speech") return;
      setError(
        event.error === "not-allowed" || event.error === "service-not-allowed"
          ? "Allow microphone access to record by voice."
          : "Couldn't hear that — try again.",
      );
    };

    recognition.onend = () => {
      setIsRecording(false);
      const text = textRef.current.trim();
      recognitionRef.current = null;
      const callback = finishRef.current;
      finishRef.current = null;
      if (text) callback?.(text);
    };

    recognitionRef.current = recognition;
    try {
      recognition.start();
      setIsRecording(true);
    } catch {
      setError("Couldn't start recording — try again.");
    }
  }, []);

  // Abort any in-flight recognition if the screen unmounts.
  useEffect(() => () => recognitionRef.current?.abort(), []);

  return { supported, isRecording, transcript, error, start, stop };
}
