//
//  EventTarget.swift
//  Exokit
//
//  Created by hyperandroid on 11/09/2018.
//  Copyright © 2018 WebMixedReality. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JSEventTarget : JSExport {
    func addEventListener(_ forEvent: String , _ callback: JSValue) -> Void
    func removeEventListener(_ forEvent: String, _ callback: JSValue) -> Void
    func dispatchEvent(_ e: JSValue) -> Void

    static func create() -> Any;
}

class EventTarget : NSObject, JSEventTarget {
    
    // map of string -> javascript function
    fileprivate var eventListeners: [String:[JSManagedValue]] = [:]
    fileprivate var onEventListeners: [String:JSManagedValue] = [:]
    
    override init() {
        super.init()
    }
    
    deinit {
        for arrcallback in eventListeners.values {
            for callback in arrcallback {
                JSValueUnprotect(callback.value.context.jsGlobalContextRef, callback.value.jsValueRef)
            }
        }
        eventListeners.removeAll()
    }
    
    class func create() -> Any {
        return EventTarget()
    }
    
    func addEventListener(_ forEvent: String, _ callback: JSValue ) -> Void {
        
        if callback.isNull || callback.isUndefined {
            JSContext.current().exception = JSValue(newErrorFromMessage: "addEventListener with wrong callback.", in: JSContext.current())
            return
        }
        
        var callbacks = eventListeners[forEvent]
        
        if callbacks == nil {
            callbacks = []
        }
        
        JSValueProtect(JSContext.current().jsGlobalContextRef, callback.jsValueRef)
        callbacks!.append(JSManagedValue(value: callback, andOwner: self))
        eventListeners.updateValue(callbacks!, forKey: forEvent)
    }

    func removeEventListener(_ forEvent: String, _ callback: JSValue ) -> Void {
        if callback.isNull || callback.isUndefined {
            return
        }

        guard let callbacks = eventListeners[forEvent] else {
            return
        }
        
        var nc: [JSManagedValue] = []
        for rcallback in callbacks {
            if !callback.isEqual(to: callback) {
                nc.append(rcallback)
            } else {
                JSValueProtect(JSContext.current().jsGlobalContextRef, rcallback.value.jsValueRef)
            }
        }
        
        eventListeners[forEvent] = nc
    }

    func dispatchEvent(_ vevent: JSValue) {
        
        if vevent.isNull || vevent.isUndefined {
            return
        }
        
        if !vevent.isInstance(of: Event.self) {
            JSContext.current().exception = JSValue(newErrorFromMessage: "argument 1 must be of type Event", in: JSContext.current())
            return
        }
        
        let event: JSEvent = vevent.toObjectOf(Event.self) as! JSEvent
        
        dispatchEventImpl(event)
    }
    
    func dispatchEventImpl(_ event: JSEvent) {
        
        guard let callbacks = eventListeners[event.type] else {
            return
        }

        let args = [event]
        
        for callback in callbacks {
            callback.value.call(withArguments: args)
        }
        
        if let callback = onEventListeners[event.type] {
            callback.value.call(withArguments: args)
        }
    }
}
