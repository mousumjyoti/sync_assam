# SRT Sync — word-synced subtitles generator

Flutter Android app that transcribes audio with **Google Cloud Speech-to-Text v2**
(Assamese `as-IN`, Hindi `hi-IN`, English `en-US`) and generates `.srt` subtitle
files grouped by a selectable number of words per line, with a live synced preview.

## Features
- Pick an audio file from the device (mp3, m4a, aac, wav, ogg, flac, amr, mp4, webm).
- Choose language and **how many words to show per subtitle line** (1–10).
- Short audio (≤ ~60 s, ≤ 10 MB): transcribed synchronously with inline base64 —
  no Cloud Storage needed.
- Longer audio: uploaded to your Cloud Storage bucket, transcribed with
  `batchRecognize`, result fetched inline, temp object deleted automatically.
- Karaoke-style preview synced to audio playback with the current word highlighted.
- Export the standard `.srt` file via the Android share sheet; toggle raw SRT view.

## Setup (one time, Google Cloud)
1. In [Google Cloud Console](https://console.cloud.google.com/), create/select a project
   and enable **Cloud Speech-to-Text API**.
2. **IAM & Admin → Service accounts → Create service account**, then grant it the
   role **Cloud Speech Client** (`roles/speech.client`) on that project. There is
   **no** role called "Cloud Speech-to-Text API User" — granting a nonexistent
   role silently leaves the account with no `speech.recognizers.recognize`
   permission and the API returns 403.
3. **Keys → Add key → Create new key → JSON** and download the file.
4. (Only for audio longer than 60 s) create a Cloud Storage bucket and grant the
   service account **Storage Object Admin** on it.
5. In the app: **Settings (gear icon) → paste the full service-account JSON**, pick
   the API location (default `us-central1`). Regional locations are routed to their
   own endpoint (e.g. `asia-southeast1-speech.googleapis.com`); `global` uses
   `speech.googleapis.com`. Assamese `as-IN` with model `chirp_2` works in global,
   us-central1, us, eu, europe-west4, asia-southeast1. For a regional location, the
   storage bucket must be in the same region. Enter the bucket name if you need
   long-file support, and save.

> Note: a plain `AIza...` API key does **not** work with Speech-to-Text v2 REST;
> it requires an OAuth token, which this app mints from the service account JSON.

## Security note
The service-account JSON is stored unencrypted in app preferences. This is
acceptable for a personal tool on your own device. Do **not** ship the app to
others with your key baked in — anyone with the APK could extract it.

## Run
```
flutter pub get
flutter run
```

## Tests
```
flutter test
```
