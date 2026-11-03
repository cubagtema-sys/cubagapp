import Flutter
import UIKit
import EventKit
import EventKitUI
import Foundation

extension Date {
      init(milliseconds:Double) {
          self = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
      }
}

var statusBarStyle = UIApplication.shared.statusBarStyle
public class Add2CalendarPlugin: NSObject, FlutterPlugin {
  // Captured by `presentCalendarModalToAddEvent` and invoked by
  // EKEventEditViewDelegate so the Flutter Future<bool> resolves with
  // .saved → true, .canceled|.deleted → false. Closes #135.
  private var pendingResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "add_2_calendar", binaryMessenger: registrar.messenger())
    let instance = Add2CalendarPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private func completePendingResult(_ success: Bool) {
    pendingResult?(success)
    pendingResult = nil
  }

 public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      if call.method == "add2Cal" {
        // Reject re-entry while a modal is already in flight. The
        // singleton-shared pendingResult slot would otherwise orphan the
        // first Future and resolve the second with the first modal's
        // action. Reject the new call without disturbing the in-flight one.
        guard pendingResult == nil else {
          result(false)
          return
        }
        let args = call.arguments as! [String:Any]
        pendingResult = result
        addEventToCalendar(from: args)
      }
    }

    private func addEventToCalendar(from args: [String:Any]) {
        let eventStore = EKEventStore()
        
        if #available(iOS 17, *) {
            let authStatus = EKEventStore.authorizationStatus(for: .event)
            switch authStatus {
            case .fullAccess, .writeOnly, .authorized:
                self.saveOrPresentEvent(from: args)
            case .notDetermined:
                eventStore.requestWriteOnlyAccessToEvents { [weak self] granted, error in
                    if granted {
                        self?.saveOrPresentEvent(from: args)
                    } else {
                        eventStore.requestFullAccessToEvents { [weak self] fullGranted, _ in
                            if fullGranted {
                                self?.saveOrPresentEvent(from: args)
                            } else {
                                self?.completePendingResult(false)
                            }
                        }
                    }
                }
            case .denied, .restricted:
                completePendingResult(false)
            @unknown default:
                completePendingResult(false)
            }
        } else {
            let authStatus = getAuthorizationStatus()
            switch authStatus {
            case .authorized:
                self.saveOrPresentEvent(from: args)
            case .notDetermined:
                eventStore.requestAccess(to: .event) { [weak self] (granted, error) in
                    if granted {
                        self?.saveOrPresentEvent(from: args)
                    } else {
                        self?.completePendingResult(false)
                    }
                }
            case .denied, .restricted:
                completePendingResult(false)
            default:
                completePendingResult(false)
            }
        }
    }

    private func saveOrPresentEvent(from args: [String:Any]) {
        let store = EKEventStore()
        let title = args["title"] as! String
        let description = args["desc"] is NSNull ? nil: args["desc"] as? String
        let location = args["location"] is NSNull ? nil: args["location"] as? String
        let timeZone = args["timeZone"] is NSNull ? nil: TimeZone(identifier: args["timeZone"] as! String)
        let startDate = Date(milliseconds: (args["startDate"] as! Double))
        let endDate = Date(milliseconds: (args["endDate"] as! Double))
        let alarmInterval = args["alarmInterval"] as? Double
        let allDay = args["allDay"] as! Bool
        let url = args["url"] as? String

        let event = createEvent(eventStore: store, alarmInterval: alarmInterval, title: title, description: description, location: location, timeZone: timeZone, startDate: startDate, endDate: endDate, allDay: allDay, url: url, args: args)

        let targetCalendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) ?? store.calendars(for: .event).first

        if let cal = targetCalendar {
            event.calendar = cal
            do {
                try store.save(event, span: .thisEvent, commit: true)
                OperationQueue.main.addOperation {
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                    self.completePendingResult(true)
                }
                return
            } catch {
                print("[Add2Calendar] Direct calendar save failed: \(error). Falling back to modal presentation.")
            }
        }

        OperationQueue.main.addOperation {
            self.presentEventCalendarDetailModal(event: event, eventStore: store)
        }
    }
    
    private func createEvent(eventStore: EKEventStore, alarmInterval: Double?, title: String, description: String?, location: String?, timeZone: TimeZone?, startDate: Date?, endDate: Date?, allDay: Bool, url: String?, args: [String:Any]) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        if let alarm = alarmInterval{
            event.addAlarm(EKAlarm(relativeOffset: alarm*(-1)))
        }
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        if (timeZone != nil) {
            event.timeZone = timeZone
        }
        if (location != nil) {
            event.location = location
        }
        if (description != nil) {
            event.notes = description
        }
        if let url = url{
            event.url = URL(string: url);
        }
        event.isAllDay = allDay
        
        if let recurrence = args["recurrence"] as? [String:Any]{
            let interval = recurrence["interval"] as! Int
            let frequency = recurrence["frequency"] as! Int
            let end = recurrence["endDate"] as? Double// Date(milliseconds: (args["startDate"] as! Double))
            let ocurrences = recurrence["ocurrences"] as? Int
            
            let recurrenceRule = EKRecurrenceRule.init(
                recurrenceWith: EKRecurrenceFrequency(rawValue: frequency)!,
                interval: interval,
                end: ocurrences != nil ? EKRecurrenceEnd.init(occurrenceCount: ocurrences!) : end != nil ? EKRecurrenceEnd.init(end: Date(milliseconds: end!)) : nil
            )
            event.recurrenceRules = [recurrenceRule]
        }
        
        return event
    }

    private func getAuthorizationStatus() -> EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: EKEntityType.event)
    }
    
    // Present edit event calendar modal as pageSheet
    func presentEventCalendarDetailModal(event: EKEvent, eventStore: EKEventStore) {
        let eventModalVC = EKEventEditViewController()
        eventModalVC.event = event
        eventModalVC.eventStore = eventStore
        eventModalVC.editViewDelegate = self
        eventModalVC.modalPresentationStyle = .pageSheet
        
        if let presenter = topPresentedViewController() {
            presenter.present(eventModalVC, animated: true, completion: nil)
        } else {
            completePendingResult(false)
        }
    }

    // CUBAG patch: topmost view controller of the foreground window scene,
    // walking up any already-presented modal so present() never collides.
    private func topPresentedViewController() -> UIViewController? {
        var root: UIViewController?
        if #available(iOS 13, *) {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let activeScene = scenes.first { $0.activationState == .foregroundActive }
                ?? scenes.first { $0.activationState == .foregroundInactive }
                ?? scenes.first
            let window = activeScene?.windows.first { $0.isKeyWindow }
                ?? activeScene?.windows.first
            root = window?.rootViewController
        } else {
            root = UIApplication.shared.keyWindow?.rootViewController
        }
        var top = root
        while let presented = top?.presentedViewController {
            if presented.isBeingDismissed {
                break
            }
            top = presented
        }
        return top
    }
}

extension Add2CalendarPlugin: EKEventEditViewDelegate {
    
    public func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        // Resolve the Future only after the modal is fully off-screen.
        // Firing pendingResult while dismiss is still animating lets a
        // caller's .then() / await-next re-enter add2Cal mid-dismissal,
        // which UIKit silently drops.
        let saved = (action == .saved)
        controller.dismiss(animated: true, completion: {
            UIApplication.shared.statusBarStyle = statusBarStyle
            self.completePendingResult(saved)
        })
    }
}
