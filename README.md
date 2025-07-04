# MasterAudioController4mac (MAC4MAC)

![MAC4MAC Logo](./Assets/AppIcon.png)  
*Centralized audio control utility tailored for audiophiles and Mac music enthusiasts.*

---

## Overview

**MasterAudioController4mac (MAC4MAC)** is a lightweight macOS menu bar app designed to intelligently manage and optimize your Apple Music playback experience. It automatically detects the sample rate of the currently playing track and adjusts your Mac's audio output sample rate accordingly—ensuring pristine, bit-perfect audio playback without manual intervention.

Beyond seamless sample rate switching, MAC4MAC also provides:

- Intuitive menu bar controls to override sample rate on the fly.
- Automatic organization of your Apple Music library into sample rate-based playlists.
- Persistent logging of playback sample rates and tracks for easy review.
- Quick access to Audio MIDI Setup.
- A professional and unobtrusive menu bar presence.

This app is perfect for audiophiles who demand precise control over their Mac audio chain without the hassle of constant manual configuration.

---

## Features

- **Automatic Sample Rate Switching**  
  Detects and switches your Mac's audio output sample rate in real-time as Apple Music plays tracks with varying sample rates.

- **Sample Rate Override**  
  From the menu bar, view and select from all supported sample rates of your current output device.

- **Playlist Automation**  
  Creates and updates playlists in Apple Music categorized by sample rate (e.g., "44 kHz", "96 kHz"), adding tracks automatically for easy organization.

- **Detailed Playback Logging**  
  Logs sample rates and track information persistently to a log file located at:  
  `~/Library/Caches/MAC4MAC.log`

- **Quick Access**  
  Open Audio MIDI Setup directly from the app menu for advanced audio configurations.

- **Low System Impact**  
  Lightweight, efficient, and built exclusively for macOS without additional dependencies.

---

## Installation

1. **Download the latest release** from the [GitHub Releases page](https://github.com/sifaralways/Mac4Mac/releases).  
2. Move the app to your Applications folder.  
3. Launch MAC4MAC. macOS will prompt you to grant **Automation permissions**—please allow access to control the Music app.  
4. (Optional) Adjust audio device settings in **Audio MIDI Setup** as needed.

---

## Usage

- **Menu Bar Icon:** Displays the current sample rate of your audio output.  
- **Override Sample Rate:** Click the menu bar icon and select a supported sample rate from the “Override Sample Rate” submenu.  
- **Playback Monitoring:** The app automatically detects track changes and adjusts sample rates accordingly.  
- **Playlist Management:** Sample rate-specific playlists are updated in Apple Music as you play tracks.  
- **Logs:** Review logs in `~/Library/Caches/MAC4MAC.log` for detailed playback and sample rate history.

---

## Permissions & Privacy

MAC4MAC requires **Automation permissions** to control the Music app for playlist management and track info fetching. The app only reads playback metadata and does not collect or transmit any personal user data.

---

## Troubleshooting

- If automatic sample rate switching does not work, ensure the app has been granted Automation permissions in **System Settings > Privacy & Security > Automation**.  
- Verify your audio output device supports the sample rates you want to switch to.  
- Restart the app after granting permissions or changing system audio settings.

---

## Development & Contribution

This project is open source and welcomes contributions! Please fork the repo, create feature branches, and submit pull requests for review.

For major changes, please open an issue first to discuss your ideas.

---

## Credits

- The original concept and inspiration come from [vincentneo’s SampleRateMenuBar](https://github.com/vincentneo/SampleRateMenuBar). This project builds upon and extends that foundation.  
- Developed and maintained by Akshat Singhal.

---

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

---

Thank you for using **MasterAudioController4mac** — your Mac’s audio deserves precision and elegance.
