# 🎧 MAC4MAC – Master Audio Controller for Mac

**Finally, bit-perfect audio from Apple Music on your Mac — now with iPhone remote control.**

MAC4MAC is a complete audio control ecosystem: a lightweight menu bar app that automatically switches your system's audio sample rate to match your Apple Music tracks, plus a beautiful iOS companion app for remote control. No more manual adjustments, no more wondering if you're getting the best quality — just perfect audio, everywhere.

---

## 🚀 Quick Start

### Mac App (Free)
1. **Download** the latest version from [Releases](https://github.com/sifaralways/Mac4Mac/releases/latest)
2. **Move** MAC4MAC.app to your Applications folder
3. **Launch** the app — you'll see a 🎵 icon in your menu bar
4. **Grant permissions** when prompted (needed to detect track changes)
5. **Play music** and watch the magic happen!

### iOS Remote App Coming Soon (Premium)
1. **Download** MAC4MAC Remote from the App Store
2. **Connect** to your Mac automatically or manually
3. **Control** your music from anywhere in your home
4. **Enjoy** Live Activities in your Dynamic Island!
![image](https://github.com/user-attachments/assets/11c2c81e-ed2c-4712-9eba-3bd9fba765fa)
![image](https://github.com/user-attachments/assets/428150ad-4d5a-4bf4-b10c-a9773eae2239)
![image](https://github.com/user-attachments/assets/b338601c-b48f-4e7e-9cca-357ef55fedf7)
![image](https://github.com/user-attachments/assets/d567aace-2260-4862-90cb-610ee244ffa2)

> **Requires macOS Monterey (12.0) or later • iOS 16.0+ for remote features**

---

## ✨ What It Does

### 🖥️ **Mac App Features**
🎵 **Smart Detection** — Automatically detects the sample rate of your current Apple Music track  
🎚️ **Instant Switching** — Changes your system audio output to match perfectly  
📊 **Live Display** — Shows current sample rate and audio device in your menu bar  
📂 **Smart Playlists** — Optionally organizes your music by quality (44.1 kHz, 96 kHz, etc.)  
🔧 **Manual Control** — Override sample rates when you need to  
🎛️ **Easy Access** — Quick link to Audio MIDI Setup for advanced users  

### 📱 **iOS Remote App Features**
🎮 **Full Music Control** — Play, pause, skip tracks from your iPhone  
📱 **Live Audio Stats** — See sample rate, bit depth, and audio quality in real-time  
🎨 **Beautiful Interface** — Gorgeous album artwork with smooth animations  
🔍 **Auto-Discovery** — Finds your Mac automatically on your network  
🏝️ **Live Activities** — Track info right in your Dynamic Island & lock screen  
📱 **Home Screen Widgets** — See what's playing without opening the app  
🔄 **Background Sync** — Stays updated even when the app is closed  

---

## 📱 iOS Remote Control

**Control your Mac's music from anywhere in your home.**

The MAC4MAC iOS app turns your iPhone into a premium remote control for your Mac's audio system. Perfect for:

- **🛋️ Living Room Listening** — Control from your couch without leaving the sweet spot
- **🛏️ Bedroom Audio** — Skip tracks while relaxing in bed  
- **🏠 Whole Home Audio** — Manage your music from any room
- **🎧 Critical Listening** — Monitor audio quality metrics in real-time
- **🎵 Music Discovery** — See which tracks are available in hi-res

### Remote Features Include:
- **Real-time track information** with album artwork
- **Sample rate and bit depth display** — know your audio quality at a glance
- **Playback controls** — play, pause, previous, next
- **Connection status** — always know if you're connected to your Mac
- **Network discovery** — automatically finds MAC4MAC on your network
- **Manual connection** — connect via IP address if needed

### Live Activities & Widgets
- **Dynamic Island integration** — see current track and sample rate
- **Lock screen widgets** — control music without unlocking
- **Home screen widgets** — quick glance at what's playing

---

## 📱 Setting Up Remote Control

### Network Requirements
- **Same WiFi network** — Mac and iPhone must be connected to the same network
- **No additional setup** — MAC4MAC automatically creates the connection
- **Firewall friendly** — uses standard ports for communication

### Connection Steps
1. **Launch MAC4MAC** on your Mac (remote server starts automatically)
2. **Open iOS app** and tap "Find My Mac"
3. **Select your Mac** from the discovered devices
4. **Start controlling** your music remotely!

### Troubleshooting Remote Connection
- Ensure both devices are on the same WiFi network
- Check that MAC4MAC is running on your Mac
- Try manual connection using your Mac's IP address
- Restart both apps if connection fails

---

## 🎯 Perfect For

- **Audiophiles** who want bit-perfect playback from Apple Music
- **Music producers** working with high-resolution audio
- **Home audio enthusiasts** who want convenient remote control
- **Apple Music subscribers** with lossless/hi-res libraries
- **Anyone** tired of manually switching sample rates
- **iPhone users** who want premium music control from their device

---

## 🔧 Using MAC4MAC

### Mac Menu Bar Display
The 🎵 icon shows your current sample rate at a glance:
- `🎵 44.1 kHz` — Standard quality
- `🎵 96.0 kHz` — Hi-Res audio  
- `🎵 192.0 kHz` — Ultra Hi-Res

### Mac Menu Options
Click the menu bar icon to access:

| Option | What It Does |
|--------|-------------|
| 🎧 **Device Info** | Shows your current audio output device |
| 📈 **Sample Rate** | Current system sample rate |
| 🎚️ **Override Sample Rate** | Manually set a specific rate |
| 🛠️ **Features** | Toggle app features on/off |
| 🎛️ **Audio MIDI Setup** | Opens macOS audio settings |

### Feature Toggles
Customize MAC4MAC's behavior:

- ✅ **Verbose Logging** — Detailed activity logs for troubleshooting
- ✅ **Playlist Creation** — Auto-organize tracks by sample rate  
- 🚫 **Real-Time DSP** — Advanced audio processing (coming soon)
- 🚫 **AI Analysis** — Intelligent audio optimization (coming soon)

---

## 🔒 Permissions Setup

### Mac App Permissions
MAC4MAC needs permission to monitor Apple Music:

**First Launch:** You'll see a permission dialog — click **"OK"** to allow access

**Manual Setup (if needed):**
1. Open **System Settings** → **Privacy & Security** → **Automation**
2. Find **MAC4MAC** in the list
3. Enable **Music** checkbox

### iOS App Permissions
The iOS remote app works automatically once connected — no special permissions needed!

---

## 📂 Smart Playlists (Optional)

When enabled, MAC4MAC creates playlists organized by audio quality:

- 📁 **MAC4MAC 44.1 kHz** — Standard quality tracks
- 📁 **MAC4MAC 96.0 kHz** — Hi-Res audio  
- 📁 **MAC4MAC 192.0 kHz** — Ultra Hi-Res

Tracks are automatically added as you listen. Perfect for discovering which songs in your library are available in higher quality!

---

## 💡 Tips & Tricks

### Mac App
- **Launch at startup** — Add MAC4MAC to your Login Items in System Settings
- **Check your library** — Use the auto-created playlists to see which songs are hi-res
- **Monitor activity** — Enable verbose logging to see exactly what's happening
- **Audio device switching** — MAC4MAC works with any Core Audio device

### iOS Remote App
- **Keep app open** during listening sessions for best Live Activity experience
- **Add widgets** to your home screen for quick music info
- **Use manual IP** if auto-discovery doesn't find your Mac
- **Background refresh** keeps the app updated even when closed

---

## 🔧 Troubleshooting

### Mac App Issues

**App Not Detecting Tracks?**
- Make sure MAC4MAC has Automation permissions
- Restart both MAC4MAC and Apple Music
- Check that you're playing from your library (not just streaming)

**Sample Rate Not Changing?**
- Verify your audio device supports the target sample rate
- Try manually overriding from the menu first
- Open Audio MIDI Setup to check device capabilities

**Playlists Not Creating?**
- Enable "Playlist Creation" in the Features menu
- Make sure tracks are in your Apple Music library
- Streaming-only tracks can't be added to playlists

### iOS Remote Issues

**Can't Find Mac?**
- Ensure both devices are on the same WiFi network
- Make sure MAC4MAC is running on your Mac
- Try manual connection with your Mac's IP address

**Connection Keeps Dropping?**
- Check WiFi signal strength on both devices
- Restart MAC4MAC on your Mac
- Force quit and reopen the iOS app

**Live Activities Not Working?**
- Ensure iOS 16.0+ and Live Activities are enabled in Settings
- Keep the iOS app open during music playback
- Check that Focus/Do Not Disturb isn't blocking notifications

---

## 🎵 Why MAC4MAC?

macOS still doesn't automatically match sample rates to your music. This means:
- Your 192 kHz tracks might play at 44.1 kHz (downsampled)
- You're not getting the quality you're paying for
- Manual switching is tedious and easy to forget

**MAC4MAC fixes this automatically**, ensuring you always get bit-perfect audio from Apple Music. The iOS remote app adds **premium convenience** — control your Mac's music from anywhere in your home while monitoring audio quality in real-time.

---

## 💰 Pricing

- **🖥️ MAC4MAC (Mac App)** — **Free** forever
- **📱 MAC4MAC Remote (iOS App)** — **Premium** companion available on the App Store

The Mac app provides all core functionality for free. The iOS remote app is a premium addition for users who want convenient remote control and advanced mobile features.

---

## 🤝 Support

Having issues? Found a bug? Have a feature request?

- 📧 **Contact:** [Create an issue](https://github.com/sifaralways/Mac4Mac/issues)
- 📝 **Logs:** Check `~/Library/Caches/MAC4MAC.log` for troubleshooting
- 🔄 **Updates:** Watch the repository for new releases
- 📱 **iOS Support:** Use the in-app feedback option in the iOS remote app

---

## 📄 License

MIT License — Free to use and enjoy!

**Created with ❤️ for the Apple Music community**

*Experience bit-perfect audio the way it was meant to be heard.*
