# Chromecast Setup

Stream audiobooks from AudioBooth to Google Nest, Google Home, and Chromecast devices.

---

## How to Cast

1. Connect your iPhone to the same Wi-Fi network as your Cast device.
2. Open any audiobook in AudioBooth and tap to view the full player.
3. Tap the **Cast** button in the top toolbar. When prompted by iOS, tap **Allow** for Local Network access.
4. Select your speaker or TV from the list.

---

## Recommended Connection: Local `http://`

For home setups, connect AudioBooth to your server using its local IP over HTTP:
```
http://<server-local-ip>:13378
```

---

## Known Blockers & Gotchas

* **Playback Stuck at `0:00` (Self-Signed Certificates):**  
  Chromecast firmware rejects self-signed SSL certificates. If using `https://`, your server must have a publicly trusted certificate (e.g., Let's Encrypt with `fullchain.pem`). Otherwise, switch your AudioBooth server URL to local `http://`.
* **No Cast Button / No Devices Found:**  
  iOS requires permission to scan your network. Go to iPhone **Settings** > **AudioBooth** and ensure **Local Network** is enabled. Make sure your phone is not on cellular data or a Guest Wi-Fi network.
* **Chromecast Cannot Reach Server:**  
  The Chromecast fetches audio directly from the server URL saved in your app. The Chromecast hardware must be able to reach that IP or domain and port over your network.
* **Audio Stalls or Won't Scrub (Reverse Proxies):**  
  If using Nginx or another reverse proxy, disable buffering (`proxy_buffering off;`) and ensure HTTP Range requests (`206 Partial Content`) are passed through.
