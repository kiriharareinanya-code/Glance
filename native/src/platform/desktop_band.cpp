#include "platform/desktop_band.h"

namespace glance {

HWND FindDesktopBand() {
  // 桌面图标层（SHELLDLL_DefView）绝大多数时候挂在 Progman 下；装了
  // Wallpaper Engine 这类动态壁纸软件后，shell 会把图标层挪进一个 WorkerW。
  // 磁贴要"贴着桌面走"，认的就是承载图标层的这个顶层窗口。
  const HWND progman = ::FindWindowW(L"Progman", nullptr);
  if (progman != nullptr &&
      ::FindWindowExW(progman, nullptr, L"SHELLDLL_DefView", nullptr) != nullptr) {
    return progman;
  }
  HWND worker = nullptr;
  while (true) {
    worker = ::FindWindowExW(nullptr, worker, L"WorkerW", nullptr);
    if (worker == nullptr) break;
    if (::FindWindowExW(worker, nullptr, L"SHELLDLL_DefView", nullptr) != nullptr) {
      return worker;
    }
  }
  // 兜底：没找到图标层就认 Progman（壁纸总画在它身上）；它也可能是 nullptr，
  // 调用方自行跳过这一拍。
  return progman;
}

bool KeepAboveDesktopBand(HWND hwnd) {
  if (hwnd == nullptr || !::IsWindowVisible(hwnd) || ::IsIconic(hwnd)) return false;
  const HWND band = FindDesktopBand();
  if (band == nullptr || band == hwnd) return false;

  // 从 Z 序顶往下数，先碰到谁谁在上面：先碰到桌面带 = 桌面被"显示"了，
  // 磁贴正被壁纸+图标盖着；先碰到磁贴 = 位置正常，什么都不用做。
  bool band_above = false;
  for (HWND it = ::GetWindow(::GetDesktopWindow(), GW_CHILD); it != nullptr;
       it = ::GetWindow(it, GW_HWNDNEXT)) {
    if (it == hwnd) break;
    if (it == band) {
      band_above = true;
      break;
    }
  }
  if (!band_above) return false;

  // 把磁贴插到桌面带正上方。SetWindowPos 的 hwndInsertAfter 语义是
  // "新位置上面挨着的那个窗口"，所以要传桌面带现在的上邻。
  // 注意：窗口过程里的 WM_WINDOWPOSCHANGING 默认会把窗口压回最底，
  // 这次抬升要先把门闩打开（见 WinWindow::set_allow_z_change）。
  const HWND above_band = ::GetWindow(band, GW_HWNDPREV);
  // above_band == nullptr 意味着桌面带已经在 Z 序最顶（Win+D 那种显示桌面
  // 状态）。此时把磁贴插到 nullptr 位置等于 HWND_TOP——磁贴会盖住所有窗口，
  // 用户看到的就是莫名其妙全局置顶。宁可这一拍不动：等桌面带回到正常
  // 位置，下一拍再处理。
  if (above_band == nullptr) return false;
  return ::SetWindowPos(hwnd, above_band, 0, 0, 0, 0,
                        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE) != FALSE;
}

}  // namespace glance
