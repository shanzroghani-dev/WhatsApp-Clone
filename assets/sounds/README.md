# Ringtone Audio File

To add a WhatsApp-like ringtone to your app:

## Option 1: Add a custom ringtone.mp3 file

1. Find or download a ringtone audio file (MP3 format recommended)
2. Rename it to `ringtone.mp3`
3. Place it in this directory: `assets/sounds/ringtone.mp3`

## Option 2: Use online ringtone (current fallback)

The app currently uses an online ringtone as a fallback if no local file is found.
This requires an internet connection to work.

## Recommended Ringtone Sources:

- **Free Ringtones**: https://www.zedge.net/find/ringtones
- **Simple Phone Ring**: https://www.soundjay.com/phone-sounds.html  
- **WhatsApp Tone Style**: Search for "phone calling ringtone" on freesound.org

## Requirements:

- **Format**: MP3 (recommended) or WAV
- **Duration**: 3-5 seconds (will loop automatically)
- **Volume**: Normalized audio for consistent volume
- **File name**: Must be exactly `ringtone.mp3`

## Testing:

After adding the ringtone file:
1. Run `flutter pub get`
2. Rebuild your app
3. Test by receiving an incoming call

The ringtone will play in a continuous loop until the call is answered or rejected.
