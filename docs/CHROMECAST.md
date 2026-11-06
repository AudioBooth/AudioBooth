# Chromecast & Google Cast Guide for AudioBooth

AudioBooth lets you stream audiobooks directly to Google Cast devices—including Google Nest/Home smart speakers, Nest Hubs, Chromecast with Google TV, and Cast-enabled smart TVs.

---

## Part 1: Quick Start for Listeners (No Tech Jargon)

If your AudioBooth app is already logged in and playing audiobooks on your phone, casting to your Google speaker takes four taps:

1. **Connect to Wi-Fi:** Make sure your iPhone is on your home Wi-Fi (not on cellular data or a "Guest" Wi-Fi network).
2. **Open Your Audiobook:** Tap any book in AudioBooth and open the full player screen.
3. **Tap the Cast Button:** In the top toolbar (next to the AirPlay icon), tap the **Cast** button (looks like a TV screen with Wi-Fi waves in the corner).
   - *First time only:* If iOS asks *"AudioBooth would like to find and connect to devices on your local network,"* tap **Allow**.
4. **Select Your Speaker:** Tap your speaker or TV from the list. The book will begin playing through your speaker!

### Controls & Voice Commands
- **From Your Phone:** Use the play/pause button, jump buttons (15s/30s), or scrub the timeline. Volume can be adjusted with your iPhone's physical volume buttons.
- **Voice Commands:** You can say *"Hey Google, pause"*, *"Hey Google, resume"*, or *"Hey Google, set volume to 40%"* directly to your speaker.
- **Switch Back to Headphones:** Tap the Cast icon again and tap **Disconnect**. AudioBooth automatically restores your progress so you can resume listening on your phone.

### 💬 Audio Connected but Stuck at 0:00?
If the Cast icon connects but the audio stays stuck at 0:00, the Chromecast is likely having trouble fetching the audio file from your server. **Copy and send this text to the friend or family member who runs your Audiobookshelf server:**

> *"Hey! I'm trying to cast AudioBooth to my Google speaker. The speaker connects, but the audiobook stays stuck at 0:00. The AudioBooth guide says Chromecast devices cannot accept self-signed security certificates. Could you check if our server connection uses a publicly trusted certificate (like Let's Encrypt) or let me connect via local HTTP when I'm home?"*

---

## Part 2: Server Admin & Onboarding Guide (For Self-Hosters)

### How Streaming Works Under the Hood
When a user casts an audiobook, AudioBooth does **not** relay audio bytes through the phone. Instead:
1. AudioBooth sends a streaming session link (`/public/session/:id/track/:index`) to the Google Cast hardware.
2. The Cast device opens Google's Default Media Receiver (`CC1AD845`).
3. The Cast hardware connects directly to the Audiobookshelf server to stream the audio file.

> [!IMPORTANT]
> **Internet Access Requirement:**  
> Even when streaming a purely local `http://192.168.x.x` URL, the Chromecast **must have outbound internet access**. It connects to Google's servers (`https://www.gstatic.com`) to download the receiver web app before starting playback. Devices on firewalled IoT networks without WAN access will fail to launch the Cast session.

---

### Recommended Connection Options

#### Option A (Recommended Default): Local `http://`
For home users where the server and the Cast devices are on the same local network:
- **Server URL in AudioBooth:** `http://192.168.1.100:13378` (use the server's static LAN IP or local DNS name).
- **Why it's recommended:** 
  - Zero SSL certificate setup.
  - Zero domain configuration or external port forwarding.
  - Chromecast plays unencrypted local HTTP audio streams without certificate validation errors.

#### Option B: Remote / Domain with `https://`
If you access Audiobookshelf over the internet through a domain:
- **Requirement:** Must use a publicly trusted TLS/SSL certificate (such as **Let's Encrypt**, ZeroSSL, or Cloudflare Origin CA).
- **Full Chain Requirement:** Chromecast's BoringSSL trust store requires the complete certificate chain. Ensure your reverse proxy serves `fullchain.pem` (leaf + intermediate certificates). If your proxy only serves `cert.pem`, browsers may work but Chromecast will fail silently.
- ❌ **Self-Signed Certificates are Unsupported:** Google Cast firmware runs a locked-down operating system with a sealed trust store. There is no mechanism to import private root CAs or bypass SSL warnings. If your server uses a self-signed cert, Chromecast will abort the TLS handshake and playback will hang at `0:00`.

---

### Reverse Proxy Configuration Checklist

If you run Audiobookshelf behind Nginx, Caddy, Traefik, or Apache:

1. **HTTP Range Requests (`206 Partial Content`):**  
   Chromecast requires HTTP Range support to buffer and scrub audio. Ensure your proxy passes the `Range` and `Accept-Ranges` headers.
2. **Disable Proxy Buffering:**  
   In Nginx, set `proxy_buffering off;` for Audiobookshelf routes. Buffering multi-hundred-megabyte `.m4b` audiobook files causes long start delays and timeout errors on Chromecast.
3. **Bypass Forward-Auth / SSO:**  
   If you use Authelia, Authentik, or Cloudflare Zero Trust, whitelist the public streaming routes (`/public/*` and `/api/*`) from interactive authentication. Chromecast cannot navigate HTML login portals.
4. **Permissive CORS:**  
   The Cast receiver executes from the origin `https://www.gstatic.com`. Ensure your reverse proxy does not strip CORS headers (`Access-Control-Allow-Origin: *`).

---

## Part 3: Advanced Networking & Homelab Setups

### Multi-VLAN & Firewall Rules (e.g. pfSense, OPNsense, UniFi)
If your Chromecast devices are isolated on an **IoT VLAN** while iPhones and servers reside on separate VLANs:

1. **mDNS Reflection:**  
   Google Cast discovery relies on multicast DNS (`224.0.0.251:5353`). Enable an mDNS repeater (Avahi daemon or UniFi "Multicast DNS") between your Phone VLAN and IoT VLAN.
2. **Firewall Allow Rules:**
   - **Phone VLAN ➔ IoT VLAN:** Allow TCP ports `8008` (HTTP API) and `8009` (Cast V2 TLS control).
   - **IoT VLAN ➔ Server VLAN / Host:** Allow TCP port `13378` (or `443` for HTTPS).
   - **IoT VLAN ➔ WAN:** Allow outbound internet access (HTTPS port `443` to Google servers).

### Google Hardcoded DNS (`8.8.8.8`) & Split-Horizon DNS
Chromecast devices deliberately ignore DHCP-assigned DNS servers and query Google's public DNS servers (`8.8.8.8` and `8.8.4.4`).
- **The Issue:** If your domain (e.g. `books.example.com`) resolves to a private IP via internal split-DNS (Pi-hole, AdGuard Home), the Chromecast will ask `8.8.8.8` and receive your *public* WAN IP instead.
- **Solution:** 
  1. Ensure **NAT Loopback (NAT Reflection / Hairpinning)** is enabled on your router.
  2. Or add a firewall Port Forward / DNAT rule redirecting all outbound port `53` traffic from the IoT VLAN to your local DNS resolver.

### DNS Rebinding Protection
Routers running pfSense, OPNsense, OpenWrt, or DD-WRT block public domains that resolve to private RFC 1918 IPs (e.g. DuckDNS pointing to `192.168.1.x`).
- Add an exception in your DNS resolver configuration (e.g. `rebind-domain-ok=/yourdomain.com/`).

---

## Part 4: Troubleshooting Matrix

### Listener Troubleshooting (iPhone)

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| **No Cast button visible in player** | iOS Local Network permission was denied | Open iPhone **Settings** > **AudioBooth** > toggle **Local Network** ON. |
| **Cast list says "No devices found"** | Phone is on Cellular data or Guest Wi-Fi | Connect your iPhone to your main home Wi-Fi network. |
| **Playback stops when screen locks** | iOS background networking restricted | AudioBooth handles background sessions automatically; ensure Low Power Mode is not suspending app refresh. |

### Server & Network Troubleshooting (Admin)

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| **Cast connects, but playback stays at 0:00** | Self-signed certificate or incomplete certificate chain | Switch AudioBooth to local `http://` or install a valid Let's Encrypt certificate with `fullchain.pem`. |
| **Cast connects, but playback stays at 0:00 (IoT VLAN)** | IoT VLAN firewall blocking access to Audiobookshelf host | Add a firewall rule allowing Chromecast IP to reach Audiobookshelf IP on port `13378` / `443`. |
| **Cast icon shows, but no devices appear (VLANs)** | mDNS not traversing subnets | Enable Avahi / mDNS repeating and allow TCP `8008/8009` from phone to Cast subnet. |
| **Cast connects, but says "Brain Freeze" or drops immediately** | Chromecast blocked from public internet | Allow outbound WAN access on port 443 for Chromecast to load `gstatic.com`. |
| **Seeking or chapter skips freeze playback** | Reverse proxy does not support HTTP Range or buffers stream | Set `proxy_buffering off;` and verify `206 Partial Content` responses in reverse proxy. |
| **Domain works on phone, fails on Cast at home** | Split-DNS mismatch with Google DNS (`8.8.8.8`) | Enable NAT Loopback / Hairpinning on router, or redirect outbound port 53 to local DNS. |
