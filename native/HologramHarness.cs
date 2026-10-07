// Pixel Panic 0.4.3 generic TIFF/GIF hologram harness.
// External responsibilities are intentionally narrow: decode/verify carrier pixels,
// expose image-carried resources and exact-byte storage on 127.0.0.1, and host WebView2.
// Game rules, guest runtime, HERMIT console, state, execution schedule, and save writers
// remain image-carried content.

using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Drawing.Imaging;
using System.Security.Cryptography;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace PixelPanic.Hologram
{
    sealed class Entry
    {
        public string Name;
        public byte[] Data;
        public int Role;
        public bool Immutable;
        public byte[] Digest;
    }

    sealed class Cartridge
    {
        public byte[] FileBytes;
        public byte[] Payload;
        public List<Entry> Entries;
        public string Approval;
        public Dictionary<string, Entry> ByName;
    }

    static class Carrier
    {
        static byte[] Sha(byte[] bytes)
        {
            using (SHA256 sha = SHA256.Create())
            {
                return sha.ComputeHash(bytes);
            }
        }

        static string Hex(byte[] bytes)
        {
            return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
        }

        static uint U32(byte[] bytes, int offset)
        {
            return BitConverter.ToUInt32(bytes, offset);
        }

        internal static Cartridge Load(string path)
        {
            byte[] file = File.ReadAllBytes(path);
            if (file.Length > 4 * 1024 * 1024)
            {
                throw new Exception("Carrier exceeds 4 MiB harness profile");
            }

            List<byte[]> pages = new List<byte[]>();
            using (System.Drawing.Image image = System.Drawing.Image.FromStream(new MemoryStream(file), true, true))
            {
                FrameDimension dimension = new FrameDimension(image.FrameDimensionsList[0]);
                int frameCount = image.GetFrameCount(dimension);
                if (frameCount != 8)
                {
                    throw new Exception("Carrier must contain exactly eight frames/pages");
                }

                for (int i = 0; i < frameCount; i++)
                {
                    image.SelectActiveFrame(dimension, i);
                    using (System.Drawing.Bitmap bitmap = new System.Drawing.Bitmap(image))
                    {
                        if (bitmap.Width != 256 || bitmap.Height != 256)
                        {
                            throw new Exception("Carrier planes must be 256x256");
                        }

                        byte[] page = new byte[65536];
                        for (int y = 0; y < 256; y++)
                        {
                            for (int x = 0; x < 256; x++)
                            {
                                System.Drawing.Color color = bitmap.GetPixel(x, y);
                                if (color.R != color.G || color.R != color.B)
                                {
                                    throw new Exception("Carrier must decode as grayscale");
                                }
                                page[y * 256 + x] = color.R;
                            }
                        }
                        pages.Add(page);
                    }
                }
            }

            byte[] payload;
            byte[] root = null;
            int total = 0;
            using (MemoryStream payloadStream = new MemoryStream())
            {
                for (int i = 0; i < 8; i++)
                {
                    byte[] raw = new byte[65536];
                    for (int y = 0; y < 256; y++)
                    {
                        int shift = (y * y + 17 * y + i * 31) & 255;
                        for (int x = 0; x < 256; x++)
                        {
                            int physical = y * 256 + ((x + shift) & 255);
                            int mask = (x * 13 + y * 7 + i * 23) & 255;
                            raw[y * 256 + x] = (byte)(pages[i][physical] ^ mask);
                        }
                    }

                    if (Encoding.ASCII.GetString(raw, 0, 8) != "PPFRAME2" ||
                        U32(raw, 8) != (uint)i || U32(raw, 12) != 8)
                    {
                        throw new Exception("Invalid executable frame header");
                    }

                    int size = (int)U32(raw, 20);
                    int bodyLength = (int)U32(raw, 24);
                    int offset = (int)U32(raw, 28);
                    if (i == 0)
                    {
                        total = size;
                        root = raw.Skip(32).Take(32).ToArray();
                    }

                    if (size != total ||
                        offset != i * (65536 - 128) ||
                        root == null ||
                        !root.SequenceEqual(raw.Skip(32).Take(32)))
                    {
                        throw new Exception("Frame sequence/root mismatch");
                    }

                    byte[] body = raw.Skip(128).Take(bodyLength).ToArray();
                    byte[] bodyHash = Sha(raw.Skip(128).ToArray());
                    if (!bodyHash.SequenceEqual(raw.Skip(80).Take(32)))
                    {
                        throw new Exception("Frame digest mismatch");
                    }
                    payloadStream.Write(body, 0, body.Length);
                }

                payload = payloadStream.ToArray();
            }

            if (root == null || payload.Length != total || !Sha(payload).SequenceEqual(root))
            {
                throw new Exception("Payload root mismatch");
            }

            return Parse(file, payload);
        }

        static Cartridge Parse(byte[] file, byte[] payload)
        {
            if (payload.Length < 32 || Encoding.ASCII.GetString(payload, 0, 8) != "PPCART02")
            {
                throw new Exception("Not PPCART02");
            }

            int count = (int)U32(payload, 12);
            int total = (int)U32(payload, 20);
            if (count < 5 || count > 32 || total != payload.Length)
            {
                throw new Exception("Envelope header invalid");
            }

            List<Entry> entries = new List<Entry>();
            int end = 32 + count * 112;
            string approvalHash;

            using (MemoryStream approval = new MemoryStream())
            {
                byte[] tag = Encoding.ASCII.GetBytes("PPCODE02");
                approval.Write(tag, 0, tag.Length);

                for (int i = 0; i < count; i++)
                {
                    int directoryOffset = 32 + i * 112;
                    int zero = Array.IndexOf(payload, (byte)0, directoryOffset, 64);
                    if (zero <= directoryOffset)
                    {
                        throw new Exception("Module name invalid");
                    }

                    string name = Encoding.ASCII.GetString(payload, directoryOffset, zero - directoryOffset);
                    int offset = (int)U32(payload, directoryOffset + 64);
                    int size = (int)U32(payload, directoryOffset + 68);
                    int role = (int)U32(payload, directoryOffset + 104);
                    bool immutable = U32(payload, directoryOffset + 108) == 1;

                    if (offset != ((end + 7) & ~7) || size <= 0 || offset + size > payload.Length)
                    {
                        throw new Exception("Module bounds invalid: " + name);
                    }

                    byte[] data = new byte[size];
                    Buffer.BlockCopy(payload, offset, data, 0, size);
                    byte[] digest = Sha(data);
                    if (!digest.SequenceEqual(payload.Skip(directoryOffset + 72).Take(32)))
                    {
                        throw new Exception("Module digest mismatch: " + name);
                    }

                    Entry entry = new Entry
                    {
                        Name = name,
                        Data = data,
                        Role = role,
                        Immutable = immutable,
                        Digest = digest
                    };
                    entries.Add(entry);

                    if (immutable)
                    {
                        byte[] nameBytes = new byte[64];
                        Encoding.ASCII.GetBytes(name, 0, name.Length, nameBytes, 0);
                        approval.Write(nameBytes, 0, 64);
                        approval.Write(BitConverter.GetBytes(role), 0, 4);
                        approval.Write(BitConverter.GetBytes(1), 0, 4);
                        approval.Write(digest, 0, 32);
                    }

                    end = offset + size;
                }

                approvalHash = Hex(Sha(approval.ToArray()));
            }

            Dictionary<string, Entry> byName = entries.ToDictionary(item => item.Name, item => item);
            string[] required = new string[]
            {
                "hologram/index.html",
                "hologram/bridge.js",
                "hologram/image-reader.js",
                "console/index.html"
            };
            foreach (string name in required)
            {
                if (!byName.ContainsKey(name))
                {
                    throw new Exception("Image lacks self-contained hologram host module: " + name);
                }
            }

            return new Cartridge
            {
                FileBytes = file,
                Payload = payload,
                Entries = entries,
                Approval = approvalHash,
                ByName = byName
            };
        }
    }

    sealed class LocalMachine : IDisposable
    {
        readonly System.Net.Sockets.TcpListener listener;
        readonly Thread thread;
        readonly string basePath;
        readonly string origin;
        readonly string expectedHost;
        readonly string capability;
        readonly string workspace;
        readonly Cartridge cartridge;
        volatile bool stop;

        public string Url
        {
            get { return origin + basePath; }
        }

        public LocalMachine(Cartridge cartridgeValue, string workspaceValue)
        {
            cartridge = cartridgeValue;
            workspace = workspaceValue;
            Directory.CreateDirectory(Path.Combine(workspace, "saves"));

            byte[] capability = new byte[32];
            using (RandomNumberGenerator random = RandomNumberGenerator.Create())
            {
                random.GetBytes(capability);
            }
            this.capability = BitConverter.ToString(capability).Replace("-", "").ToLowerInvariant();
            basePath = "/" + this.capability + "/";

            // TcpListener avoids Windows HTTP.sys URL reservations. The console remains strictly
            // loopback-only and does not require an administrator-created URL ACL.
            listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            expectedHost = "127.0.0.1:" + port;
            origin = "http://" + expectedHost;

            thread = new Thread(Loop);
            thread.IsBackground = true;
            thread.Name = "PixelPanic-Hologram-127";
            thread.Start();
        }

        static byte[] Sha(byte[] bytes)
        {
            using (SHA256 sha = SHA256.Create())
            {
                return sha.ComputeHash(bytes);
            }
        }

        static string Hex(byte[] bytes)
        {
            return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
        }

        static string StatusText(int statusCode)
        {
            if (statusCode == 200) return "OK";
            if (statusCode == 201) return "Created";
            if (statusCode == 400) return "Bad Request";
            if (statusCode == 403) return "Forbidden";
            if (statusCode == 404) return "Not Found";
            if (statusCode == 405) return "Method Not Allowed";
            if (statusCode == 413) return "Payload Too Large";
            if (statusCode == 415) return "Unsupported Media Type";
            return "Error";
        }

        static void WriteResponse(Stream stream, int statusCode, string contentType, byte[] body)
        {
            string headers =
                "HTTP/1.1 " + statusCode + " " + StatusText(statusCode) + "\r\n" +
                "Content-Type: " + contentType + "\r\n" +
                "Content-Length: " + body.Length + "\r\n" +
                "Cache-Control: no-store\r\n" +
                "X-Content-Type-Options: nosniff\r\n" +
                "Referrer-Policy: no-referrer\r\n" +
                "Cross-Origin-Resource-Policy: same-origin\r\n" +
                "Permissions-Policy: camera=(), microphone=(), geolocation=(), usb=(), payment=()\r\n" +
                "Content-Security-Policy: default-src 'none'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'unsafe-inline'; connect-src 'self'; img-src data:; frame-src 'self' about:; base-uri 'none'; object-src 'none'; form-action 'none'; frame-ancestors 'none'\r\n" +
                "Connection: close\r\n\r\n";
            byte[] prefix = Encoding.ASCII.GetBytes(headers);
            stream.Write(prefix, 0, prefix.Length);
            if (body.Length != 0)
            {
                stream.Write(body, 0, body.Length);
            }
            stream.Flush();
        }

        static void WriteEmpty(Stream stream, int statusCode)
        {
            WriteResponse(stream, statusCode, "text/plain; charset=utf-8", new byte[0]);
        }

        static void WriteJson(Stream stream, object value, int statusCode)
        {
            byte[] body = Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(value));
            WriteResponse(stream, statusCode, "application/json; charset=utf-8", body);
        }

        static void WriteJson(Stream stream, object value)
        {
            WriteJson(stream, value, 200);
        }

        static void WriteBytes(Stream stream, byte[] bytes, string contentType)
        {
            WriteResponse(stream, 200, contentType, bytes);
        }

        object[] Files()
        {
            List<object> files = new List<object>();
            files.Add(new
            {
                id = "boot",
                name = "PixelPanic-Hologram.tiff",
                kind = "tiff",
                bytes = cartridge.FileBytes.Length
            });

            string saves = Path.Combine(workspace, "saves");
            foreach (string file in Directory.GetFiles(saves))
            {
                FileInfo info = new FileInfo(file);
                if (info.Length > 4 * 1024 * 1024 || (info.Attributes & FileAttributes.ReparsePoint) != 0)
                {
                    continue;
                }

                string extension = info.Extension.ToLowerInvariant();
                if (extension != ".gif" && extension != ".tif" && extension != ".tiff")
                {
                    continue;
                }

                files.Add(new
                {
                    id = "save:" + info.Name,
                    name = info.Name,
                    kind = extension == ".gif" ? "gif" : "tiff",
                    bytes = info.Length
                });
            }
            return files.ToArray();
        }

        static byte[] ReadHeaderBlock(Stream stream)
        {
            MemoryStream header = new MemoryStream();
            int state = 0;
            while (header.Length < 65536)
            {
                int value = stream.ReadByte();
                if (value < 0)
                {
                    throw new IOException("Connection closed before HTTP headers completed");
                }
                header.WriteByte((byte)value);

                if (state == 0) state = value == '\r' ? 1 : 0;
                else if (state == 1) state = value == '\n' ? 2 : 0;
                else if (state == 2) state = value == '\r' ? 3 : 0;
                else if (state == 3)
                {
                    if (value == '\n') return header.ToArray();
                    state = 0;
                }
            }
            throw new IOException("HTTP header exceeds 64 KiB");
        }

        static byte[] ReadExact(Stream stream, int length)
        {
            byte[] bytes = new byte[length];
            int offset = 0;
            while (offset < length)
            {
                int read = stream.Read(bytes, offset, length - offset);
                if (read <= 0)
                {
                    throw new IOException("Connection closed before request body completed");
                }
                offset += read;
            }
            return bytes;
        }

        static Dictionary<string, string> ParseHeaders(string[] lines)
        {
            Dictionary<string, string> headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (int i = 1; i < lines.Length; i++)
            {
                string line = lines[i];
                if (line.Length == 0) continue;
                int colon = line.IndexOf(':');
                if (colon <= 0) throw new IOException("Malformed HTTP header");
                string name = line.Substring(0, colon).Trim();
                string value = line.Substring(colon + 1).Trim();
                headers[name] = value;
            }
            return headers;
        }

        void Loop()
        {
            while (!stop)
            {
                try
                {
                    System.Net.Sockets.TcpClient client = listener.AcceptTcpClient();
                    client.ReceiveTimeout = 10000;
                    client.SendTimeout = 10000;
                    Handle(client);
                }
                catch
                {
                    if (stop) break;
                }
            }
        }

        void Handle(System.Net.Sockets.TcpClient client)
        {
            using (client)
            using (NetworkStream stream = client.GetStream())
            {
                try
                {
                    string headerText = Encoding.ASCII.GetString(ReadHeaderBlock(stream));
                    string[] lines = headerText.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                    if (lines.Length < 2) throw new IOException("Malformed HTTP request");

                    string[] request = lines[0].Split(' ');
                    if (request.Length != 3 || request[2] != "HTTP/1.1")
                    {
                        WriteEmpty(stream, 400);
                        return;
                    }

                    string method = request[0];
                    string target = request[1];
                    if (method != "GET" && method != "POST")
                    {
                        WriteEmpty(stream, 405);
                        return;
                    }
                    if (!target.StartsWith("/", StringComparison.Ordinal))
                    {
                        WriteEmpty(stream, 400);
                        return;
                    }

                    Dictionary<string, string> headers = ParseHeaders(lines);
                    string host;
                    if (!headers.TryGetValue("Host", out host) || !string.Equals(host, expectedHost, StringComparison.OrdinalIgnoreCase))
                    {
                        WriteEmpty(stream, 403);
                        return;
                    }

                    string requestOrigin;
                    if (headers.TryGetValue("Origin", out requestOrigin) && !string.Equals(requestOrigin, origin, StringComparison.OrdinalIgnoreCase))
                    {
                        WriteEmpty(stream, 403);
                        return;
                    }
                    string fetchSite;
                    if (headers.TryGetValue("Sec-Fetch-Site", out fetchSite) && string.Equals(fetchSite, "cross-site", StringComparison.OrdinalIgnoreCase))
                    {
                        WriteEmpty(stream, 403);
                        return;
                    }
                    if (method == "POST")
                    {
                        string suppliedCapability;
                        if (!headers.TryGetValue("X-Console-Capability", out suppliedCapability) ||
                            !string.Equals(suppliedCapability, capability, StringComparison.Ordinal))
                        {
                            WriteEmpty(stream, 403);
                            return;
                        }
                    }

                    int contentLength = 0;
                    string contentLengthText;
                    if (headers.TryGetValue("Content-Length", out contentLengthText))
                    {
                        if (!Int32.TryParse(contentLengthText, out contentLength) || contentLength < 0)
                        {
                            WriteEmpty(stream, 400);
                            return;
                        }
                        if (contentLength > 4 * 1024 * 1024)
                        {
                            WriteEmpty(stream, 413);
                            return;
                        }
                    }
                    byte[] body = contentLength == 0 ? new byte[0] : ReadExact(stream, contentLength);

                    int query = target.IndexOf('?');
                    string path = query >= 0 ? target.Substring(0, query) : target;
                    if (!path.StartsWith(basePath, StringComparison.Ordinal))
                    {
                        WriteEmpty(stream, 404);
                        return;
                    }
                    string route = path.Substring(basePath.Length);

                    if (method == "GET" && route == "")
                    {
                        WriteBytes(stream, cartridge.ByName["hologram/index.html"].Data, "text/html; charset=utf-8");
                        return;
                    }
                    if (method == "GET" && route == "image-reader.js")
                    {
                        WriteBytes(stream, cartridge.ByName["hologram/image-reader.js"].Data, "application/javascript; charset=utf-8");
                        return;
                    }
                    if (method == "GET" && route == "bridge.js")
                    {
                        WriteBytes(stream, cartridge.ByName["hologram/bridge.js"].Data, "application/javascript; charset=utf-8");
                        return;
                    }
                    if (method == "GET" && route == "config")
                    {
                        WriteJson(stream, new
                        {
                            origin = origin,
                            @base = basePath,
                            approval = cartridge.Approval,
                            ui = "console/index.html",
                            native = true
                        });
                        return;
                    }
                    if (method == "GET" && route == "files")
                    {
                        WriteJson(stream, new { files = Files() });
                        return;
                    }
                    if (method == "GET" && route.StartsWith("bytes/", StringComparison.Ordinal))
                    {
                        string id = Uri.UnescapeDataString(route.Substring(6));
                        if (id == "boot")
                        {
                            WriteBytes(stream, cartridge.FileBytes, "image/tiff");
                            return;
                        }
                        if (id.StartsWith("save:", StringComparison.Ordinal))
                        {
                            string name = Path.GetFileName(id.Substring(5));
                            string file = Path.Combine(workspace, "saves", name);
                            if (File.Exists(file))
                            {
                                WriteBytes(
                                    stream,
                                    File.ReadAllBytes(file),
                                    name.EndsWith(".gif", StringComparison.OrdinalIgnoreCase) ? "image/gif" : "image/tiff");
                                return;
                            }
                        }
                        WriteEmpty(stream, 404);
                        return;
                    }
                    if (method == "POST" && route == "store")
                    {
                        string contentType;
                        if (!headers.TryGetValue("Content-Type", out contentType)) contentType = "";
                        bool gif = contentType.StartsWith("image/gif", StringComparison.OrdinalIgnoreCase);
                        bool tiff = contentType.StartsWith("image/tiff", StringComparison.OrdinalIgnoreCase);
                        if (!gif && !tiff)
                        {
                            WriteEmpty(stream, 415);
                            return;
                        }
                        if (body.Length < 8)
                        {
                            WriteEmpty(stream, 415);
                            return;
                        }
                        bool gifSignature = Encoding.ASCII.GetString(body, 0, 6) == "GIF87a" || Encoding.ASCII.GetString(body, 0, 6) == "GIF89a";
                        bool littleTiff = body[0] == (byte)'I' && body[1] == (byte)'I' && ((body[2] == 42 && body[3] == 0) || (body[2] == 43 && body[3] == 0));
                        bool bigTiff = body[0] == (byte)'M' && body[1] == (byte)'M' && ((body[2] == 0 && body[3] == 42) || (body[2] == 0 && body[3] == 43));
                        if ((gif && !gifSignature) || (tiff && !(littleTiff || bigTiff)))
                        {
                            WriteEmpty(stream, 415);
                            return;
                        }

                        string extension = gif ? "gif" : "tiff";
                        string name = "PixelPanic-" + DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8) + "." + extension;
                        string file = Path.Combine(workspace, "saves", name);
                        using (FileStream output = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        {
                            output.Write(body, 0, body.Length);
                            output.Flush();
                        }
                        WriteJson(stream, new
                        {
                            name = name,
                            bytes = body.Length,
                            sha256 = Hex(Sha(body))
                        }, 201);
                        return;
                    }
                    if (method == "POST" && route == "shutdown")
                    {
                        WriteJson(stream, new { ok = true });
                        stop = true;
                        listener.Stop();
                        return;
                    }

                    WriteEmpty(stream, 404);
                }
                catch (Exception exception)
                {
                    try
                    {
                        WriteJson(stream, new { error = exception.Message }, 400);
                    }
                    catch
                    {
                    }
                }
            }
        }

        public void Dispose()
        {
            stop = true;
            try { listener.Stop(); } catch { }
        }
    }

    sealed class MainWindow : Window
    {
        readonly WebView2CompositionControl view;
        readonly LocalMachine machine;

        public MainWindow(Cartridge cartridge, string workspace)
        {
            machine = new LocalMachine(cartridge, workspace);
            Title = "Pixel Panic Processable Hologram";
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.CanResize;
            Width = Math.Min(1460, SystemParameters.WorkArea.Width * 0.95);
            Height = Math.Min(980, SystemParameters.WorkArea.Height * 0.95);
            Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(8, 15, 25));

            view = new WebView2CompositionControl();
            view.AllowExternalDrop = false;
            view.CreationProperties = new CoreWebView2CreationProperties
            {
                UserDataFolder = Path.Combine(workspace, "webview2")
            };
            Content = view;

            Loaded += OnLoaded;
            Closed += OnClosed;
        }

        async void OnLoaded(object sender, RoutedEventArgs args)
        {
            await view.EnsureCoreWebView2Async(null);
            CoreWebView2 core = view.CoreWebView2;
            if (core == null)
            {
                throw new Exception("WebView2 initialization completed without CoreWebView2");
            }

            core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsWebMessageEnabled = true;

            core.NavigationStarting += delegate(object navigationSender, CoreWebView2NavigationStartingEventArgs navigationArgs)
            {
                if (!string.Equals(navigationArgs.Uri, machine.Url, StringComparison.Ordinal))
                {
                    navigationArgs.Cancel = true;
                }
            };
            core.NewWindowRequested += delegate(object windowSender, CoreWebView2NewWindowRequestedEventArgs windowArgs)
            {
                windowArgs.Handled = true;
            };
            core.PermissionRequested += delegate(object permissionSender, CoreWebView2PermissionRequestedEventArgs permissionArgs)
            {
                permissionArgs.State = CoreWebView2PermissionState.Deny;
            };
            core.WebMessageReceived += delegate(object messageSender, CoreWebView2WebMessageReceivedEventArgs messageArgs)
            {
                try
                {
                    Dictionary<string, object> message = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(messageArgs.TryGetWebMessageAsString());
                    if (message == null || !message.ContainsKey("operation"))
                    {
                        return;
                    }

                    string operation = message["operation"] as string;
                    if (operation == "close")
                    {
                        Close();
                    }
                    else if (operation == "fullscreen")
                    {
                        WindowState = WindowState.Maximized;
                    }
                    else if (operation == "windowed")
                    {
                        WindowState = WindowState.Normal;
                    }
                }
                catch
                {
                }
            };

            view.Source = new Uri(machine.Url);
        }

        void OnClosed(object sender, EventArgs args)
        {
            machine.Dispose();
            view.Dispose();
        }
    }

    public static class Program
    {
        public static int Verify(string cartridge)
        {
            Carrier.Load(cartridge);
            return 0;
        }

        [STAThread]
        public static int Run(string cartridge, string workspace)
        {
            Cartridge loaded = Carrier.Load(cartridge);
            Application application = new Application();
            application.Run(new MainWindow(loaded, workspace));
            return 0;
        }
    }
}
