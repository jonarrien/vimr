/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Cocoa
import RxNeovimApi
import RxSwift
import MessagePack

extension NvimView {

  public func enterResizeMode() {
    self.currentlyResizing = true
    self.needsDisplay = true
  }

  public func exitResizeMode() {
    self.currentlyResizing = false
    self.needsDisplay = true
    self.resizeNeoVimUi(to: self.bounds.size)
  }

  public func currentBuffer() -> Single<NvimView.Buffer> {
    return self.api
      .getCurrentBuf()
      .flatMap { self.neoVimBuffer(for: $0, currentBuffer: $0) }
      .subscribeOn(self.scheduler)
  }

  public func allBuffers() -> Single<[NvimView.Buffer]> {
    return Single
      .zip(self.api.getCurrentBuf(), self.api.listBufs()) { (curBuf: $0, bufs: $1) }
      .map { tuple in tuple.bufs.map { buf in self.neoVimBuffer(for: buf, currentBuffer: tuple.curBuf) } }
      .flatMap(Single.fromSinglesToSingleOfArray)
      .subscribeOn(self.scheduler)
  }

  public func isCurrentBufferDirty() -> Single<Bool> {
    return self
      .currentBuffer()
      .map { $0.isDirty }
      .subscribeOn(self.scheduler)
  }

  public func allTabs() -> Single<[NvimView.Tabpage]> {
    return Single.zip(self.api.getCurrentBuf(),
                      self.api.getCurrentTabpage(),
                      self.api.listTabpages()) { (curBuf: $0, curTab: $1, tabs: $2) }
      .map { tuple in
        return tuple.tabs.map { tab in
          return self.neoVimTab(for: tab, currentTabpage: tuple.curTab, currentBuffer: tuple.curBuf)
        }
      }
      .flatMap(Single.fromSinglesToSingleOfArray)
      .subscribeOn(self.scheduler)
  }

  public func newTab() -> Completable {
    return self.api
      .command(command: "tabe", expectsReturnValue: false)
      .subscribeOn(self.scheduler)
  }

  public func `open`(urls: [URL]) -> Completable {
    return self
      .allTabs()
      .flatMapCompletable { tabs -> Completable in
        let buffers = tabs.map { $0.windows }.flatMap { $0 }.map { $0.buffer }
        let currentBufferIsTransient = buffers.first { $0.isCurrent }?.isTransient ?? false

        return Completable.concat(
          urls.map { url -> Completable in
            let bufExists = buffers.contains { $0.url == url }
            let wins = tabs.map({ $0.windows }).flatMap({ $0 })
            if let win = bufExists ? wins.first(where: { win in win.buffer.url == url }) : nil {
              return self.api.setCurrentWin(window: Api.Window(win.handle), expectsReturnValue: false)
            }

            return currentBufferIsTransient ? self.open(url, cmd: "e") : self.open(url, cmd: "tabe")
          }
        )
      }
      .subscribeOn(self.scheduler)
  }

  public func openInNewTab(urls: [URL]) -> Completable {
    return Completable
      .concat(urls.map { url in self.open(url, cmd: "tabe") })
      .subscribeOn(self.scheduler)
  }

  public func openInCurrentTab(url: URL) -> Completable {
    return self.open(url, cmd: "e")
  }

  public func openInHorizontalSplit(urls: [URL]) -> Completable {
    return Completable
      .concat(urls.map { url in self.open(url, cmd: "sp") })
      .subscribeOn(self.scheduler)
  }

  public func openInVerticalSplit(urls: [URL]) -> Completable {
    return Completable
      .concat(urls.map { url in self.open(url, cmd: "vsp") })
      .subscribeOn(self.scheduler)
  }

  public func select(buffer: NvimView.Buffer) -> Completable {
    return self
      .allTabs()
      .map { tabs in tabs.map { $0.windows }.flatMap { $0 } }
      .flatMapCompletable { wins -> Completable in
        if let win = wins.first(where: { $0.buffer == buffer }) {
          return self.api.setCurrentWin(window: Api.Window(win.handle), expectsReturnValue: false)
        }

        return self.api.command(command: "tab sb \(buffer.handle)", expectsReturnValue: false)
      }
      .subscribeOn(self.scheduler)
  }

/// Closes the current window.
  public func closeCurrentTab() -> Completable {
    return self.api
      .command(command: "q", expectsReturnValue: true)
      .subscribeOn(self.scheduler)
  }

  public func saveCurrentTab() -> Completable {
    return self.api
      .command(command: "w", expectsReturnValue: true)
      .subscribeOn(self.scheduler)
  }

  public func saveCurrentTab(url: URL) -> Completable {
    return self.api
      .command(command: "w \(url.path)", expectsReturnValue: true)
      .subscribeOn(self.scheduler)
  }

  public func closeCurrentTabWithoutSaving() -> Completable {
    return self.api
      .command(command: "q!", expectsReturnValue: true)
      .subscribeOn(self.scheduler)
  }

  public func quitNeoVimWithoutSaving() -> Completable {
    self.bridgeLogger.mark()
    return self.api
      .command(command: "qa!", expectsReturnValue: true)
      .subscribeOn(self.scheduler)
  }

  public func vimOutput(of command: String) -> Single<String> {
    return self.api
      .commandOutput(str: command)
      .subscribeOn(self.scheduler)
  }

  public func cursorGo(to position: Position) -> Completable {
    return self.api
      .getCurrentWin()
      .flatMapCompletable { curWin in self.api.winSetCursor(window: curWin, pos: [position.row, position.column]) }
      .subscribeOn(self.scheduler)
  }

  public func didBecomeMain() -> Completable {
    return self.bridge.focusGained(true)
  }

  public func didResignMain() -> Completable {
    return self.bridge.focusGained(false)
  }

  func neoVimBuffer(for buf: Api.Buffer, currentBuffer: Api.Buffer?) -> Single<NvimView.Buffer> {
    return self.api
      .bufGetInfo(buffer: buf)
      .map { info -> NvimView.Buffer in
        let current = buf == currentBuffer
        guard let path = info["filename"]?.stringValue,
              let dirty = info["modified"]?.boolValue,
              let buftype = info["buftype"]?.stringValue,
              let listed = info["buflisted"]?.boolValue
          else {
          throw Api.Error.exception(message: "Could not convert values from the dictionary.")
        }

        let url = path == "" || buftype != "" ? nil : URL(fileURLWithPath: path)

        return NvimView.Buffer(apiBuffer: buf,
                               url: url,
                               type: buftype,
                               isDirty: dirty,
                               isCurrent: current,
                               isListed: listed)
      }
      .subscribeOn(self.scheduler)
  }

  private func `open`(_ url: URL, cmd: String) -> Completable {
    return self.api
      .command(command: "\(cmd) \(url.path)", expectsReturnValue: false)
      .subscribeOn(self.scheduler)
  }

  private func neoVimWindow(for window: Api.Window,
                            currentWindow: Api.Window?,
                            currentBuffer: Api.Buffer?) -> Single<NvimView.Window> {

    return self.api
      .winGetBuf(window: window)
      .flatMap { buf in self.neoVimBuffer(for: buf, currentBuffer: currentBuffer) }
      .map { buffer in NvimView.Window(apiWindow: window, buffer: buffer, isCurrentInTab: window == currentWindow) }
  }

  private func neoVimTab(for tabpage: Api.Tabpage,
                         currentTabpage: Api.Tabpage?,
                         currentBuffer: Api.Buffer?) -> Single<NvimView.Tabpage> {

    return Single.zip(
        self.api.tabpageGetWin(tabpage: tabpage),
        self.api.tabpageListWins(tabpage: tabpage)) { (curWin: $0, wins: $1) }
      .map { tuple in
        tuple.wins.map { win in
          return self.neoVimWindow(for: win, currentWindow: tuple.curWin, currentBuffer: currentBuffer)
        }
      }
      .flatMap(Single.fromSinglesToSingleOfArray)
      .map { wins in NvimView.Tabpage(apiTabpage: tabpage, windows: wins, isCurrent: tabpage == currentTabpage) }
  }
}
