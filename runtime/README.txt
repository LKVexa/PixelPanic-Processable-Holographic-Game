Pixel Panic Hologram 0.4.4 HARD MODE external console substrate

The game, rules, guest interpreter, executable schedule, HERMIT console, state, and image-save logic remain inside the TIFF/GIF cartridge.

The external C# harness needs the Microsoft.Web.WebView2 SDK adapter and an installed WebView2 Evergreen Runtime. BOOT.cmd can provision the pinned SDK adapter on first use after explicit consent; SETUP.cmd performs the same action separately.

Pinned SDK adapter: Microsoft.Web.WebView2 1.0.4191.47
Provisioned folder:
  runtime\webview2-sdk\Microsoft.Web.WebView2.Core.dll
  runtime\webview2-sdk\Microsoft.Web.WebView2.Wpf.dll
  runtime\webview2-sdk\Microsoft.Web.WebView2.WinForms.dll
  runtime\webview2-sdk\WebView2Loader.dll
  runtime\webview2-sdk\PROVISIONED.json

0.4.3 C# harness repair (inherited unchanged by 0.4.4):
  - corrects the missing C# class-closing brace that produced CS1513;
  - removes Image/Color ambiguity and accessibility hazards;
  - explicitly references System.Core for LINQ compilation;
  - adds the WebView2 WinForms managed adapter to the pinned dependency closure;
  - uses an ordinary loopback TcpListener instead of HttpListener/HTTP.sys URL reservations.

BOOT.cmd / SETUP.cmd / VERIFY.cmd remove Mark-of-the-Web only from this package's native\*.ps1 helpers with Unblock-File, then keep RemoteSigned execution. They do NOT call Set-ExecutionPolicy and do NOT use ExecutionPolicy Bypass. MachinePolicy/UserPolicy remains authoritative.

The separate Microsoft Edge WebView2 Evergreen Runtime must also be installed on Windows.
