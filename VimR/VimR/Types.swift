/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Foundation
import RxSwift

protocol UiComponent {

  associatedtype StateType

  init(source: Observable<StateType>, emitter: ActionEmitter, state: StateType)
}

class ActionEmitter {

  let observable: Observable<Any>

  init() {
    self.observable = self.subject.asObservable().observeOn(scheduler)
  }

  func typedEmit<T>() -> ((T) -> Void) {
    return { (action: T) in
      self.subject.onNext(action)
    }
  }

  deinit {
    self.subject.onCompleted()
  }

  private let scheduler = SerialDispatchQueueScheduler(qos: .userInteractive)
  private let subject = PublishSubject<Any>()
}

class StateActionPair<S, A> {

  let modified: Bool
  let state: S
  let action: A

  init(state: S, action: A, modified: Bool = true) {
    self.modified = modified
    self.state = state
    self.action = action
  }
}

class UuidAction<A>: CustomStringConvertible {

  let uuid: String
  let payload: A

  var description: String {
    return "UuidAction(uuid: \(uuid), payload: \(String(reflecting: payload)))"
  }

  init(uuid: String, action: A) {
    self.uuid = uuid
    self.payload = action
  }
}

class UuidState<S>: CustomStringConvertible {

  let uuid: String
  let payload: S

  var description: String {
    return "UuidState(uuid: \(uuid), payload: \(String(reflecting: payload)))"
  }

  init(uuid: String, state: S) {
    self.uuid = uuid
    self.payload = state
  }
}

class Token: Hashable, CustomStringConvertible {

  var hashValue: Int {
    return ObjectIdentifier(self).hashValue
  }

  var description: String {
    return ObjectIdentifier(self).debugDescription
  }

  static func == (left: Token, right: Token) -> Bool {
    return left === right
  }
}

class Marked<T>: CustomStringConvertible {

  let mark: Token
  let payload: T

  var description: String {
    return "Marked<\(mark) -> \(self.payload)>"
  }

  convenience init(_ payload: T) {
    self.init(mark: Token(), payload: payload)
  }

  init(mark: Token, payload: T) {
    self.mark = mark
    self.payload = payload
  }

  func hasDifferentMark(as other: Marked<T>) -> Bool {
    return self.mark != other.mark
  }
}

extension Observable {

  func reduce(by reduce: @escaping (Element) -> Element) -> Observable<Element> {
    return self.map(reduce)
  }

  func apply(_ apply: @escaping (Element) -> Void) -> Observable<Element> {
    return self.do(onNext: apply)
  }

  func filterMapPair<S, A>() -> Observable<S> where Element == StateActionPair<S, A> {
    return self
      .filter { $0.modified }
      .map { $0.state }
  }
}

class UiComponentTemplate: UiComponent {

  typealias StateType = State

  struct State {

    var someField: String
  }

  enum Action {

    case doSth
  }

  required init(source: Observable<StateType>, emitter: ActionEmitter, state: StateType) {
    // set the typed action emit function
    self.emit = emitter.typedEmit()

    // init the component with the initial state "state"
    self.someField = state.someField

    // react to the new state
    source
      .observeOn(MainScheduler.instance)
      .subscribe(
        onNext: { [unowned self] state in
          print("Hello, \(self.someField)")
        }
      )
      .disposed(by: self.disposeBag)
  }

  func someAction() {
    // when the user does something, emit an action
    self.emit(.doSth)
  }

  private let emit: (Action) -> Void
  private let disposeBag = DisposeBag()

  private let someField: String
}