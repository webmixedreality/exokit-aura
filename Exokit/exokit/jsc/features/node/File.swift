//
//  File.swift
//  Exokit
//
//  Created by hyperandroid on 08/09/2018.
//  Copyright © 2018 WebMixedReality. All rights reserved.
//

import Foundation
import JavaScriptCore

enum FileStorage {
    case Bundle
    case Documents
    case Remote
}

protocol AbstractFile {

    var size: Double { get }
    var isDirectory: Bool { get }
    var exists: Bool {get}
    var path: String {get}

    func loadAsText() -> String?
    func createWithText(_ str: String) -> Bool
    func listFiles() -> [AbstractFile]
    func delete() -> Bool
    func mkdir() -> Bool
}

class RemoteFile : AbstractFile {

    var size: Double = 0
    var isDirectory: Bool = false
    var exists: Bool = false
    var path: String = ""

    init(path: String, storage: FileStorage = .Bundle) {
        self.path = path
    }

    func loadAsText() -> String? {

        do {
            return try String(contentsOf: URL.init(string: path)!, encoding: String.Encoding.utf8)
        }
        catch let error {
            print("\(error)")
        }

        return nil
    }

    func createWithText(_ str: String) -> Bool {
        return false
    }

    func listFiles() -> [AbstractFile] {
        return []
    }

    func delete() -> Bool {
        return false
    }

    func mkdir() -> Bool {
        return false
    }

}

class LocalFile : AbstractFile {

    var path: String = ""
    var isDirectory: Bool = false
    var exists: Bool = false
    var size: Double = 0
    var storage : FileStorage = .Bundle

    init(path: String, storage: FileStorage = .Bundle) {
        self.storage = storage
        self.path = LocalFile.FilePath(path: path, storage: storage)
        setFileInfo()
    }

    init(wrapped: String, storage: FileStorage = .Bundle) {
        self.path = wrapped
        self.storage = storage
        setFileInfo()
    }

    static func FilePath(path: String, storage: FileStorage) -> String {
        switch storage {
        case .Bundle:
            return "\(Bundle.main.bundlePath)/\(path)"
        case .Documents:
            let dir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
            return "\(dir)/\(path)"
        default:
            return path
        }
    }

    // filename is searched for in the bundle directory.
    private func setFileInfo() {
        var isDir: ObjCBool = false
        exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        isDirectory = isDir.boolValue

        if exists && !isDirectory {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                size = attributes[ FileAttributeKey.size ] as! Double
            }
        } else {
            size = 0
        }
    }

    func loadAsText() -> String? {
        if exists && !isDirectory {
            return try? String(contentsOfFile: path)
        }

        return nil
    }

    func listFiles() -> [AbstractFile] {
        if !isDirectory {
            return []
        }

        if let filepaths = try? FileManager.default.contentsOfDirectory(atPath: path) {
            var ret: [LocalFile] = []
            for filepath in filepaths {
                ret.append(LocalFile(wrapped: "\(path)/\(filepath)", storage: storage))
            }

            return ret
        }

        return []
    }

    func createWithText(_ str: String) -> Bool {
        do {
            try str.write(toFile: path, atomically: false, encoding: String.Encoding.utf8)
            setFileInfo()
            return true
        } catch {
            print("unexpected File.createWithText: \(error)")
            return false
        }
    }

    func delete() -> Bool {
        do {
            try FileManager.default.removeItem(atPath: path)
            setFileInfo()
            return true
        } catch {
            print("unexpected File.delete: \(error)")
            return false
        }
    }

    func mkdir() -> Bool {

        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
            setFileInfo()
            return true
        } catch {
            print("unexpected File.mkdir: \(error)")
            return false
        }
    }
}

// A native File object wrapped in a JS object
// The wrapper object if FileWrapper.
class File : Wrappable {

    var fileDelegate: AbstractFile?

    init(path: String, storage: FileStorage = .Bundle) {
        super.init()
        switch(storage) {
        case .Remote:
            fileDelegate = RemoteFile(path:path, storage: storage)
        default:
            fileDelegate = LocalFile(path: path, storage: storage)
        }
    }

    init(wrap: AbstractFile) {
        super.init()
        fileDelegate = wrap
    }

    override func cleanUp() {
        super.cleanUp()
    }

    override func getClass() -> JSClassRef! {
        return FileWrapper.ClassRef
    }

    func loadAsText() -> String? {
        return fileDelegate?.loadAsText()
    }

    func listFiles() -> [File] {

        var ret: [File] = []

        let afiles = fileDelegate?.listFiles() ?? []
        for file in afiles {
            ret.append(File(wrap: file))
        }

        return ret
    }

    func createWithText(_ str: String) -> Bool {
        return fileDelegate?.createWithText(str) ?? false
    }

    func delete() -> Bool {
        return fileDelegate?.delete() ?? false
    }

    func mkdir() -> Bool {
        return fileDelegate?.mkdir() ?? false
    }
}

// A javascript wrapper for a native File object.
struct FileWrapper {

    static let ClassName: String = "File"
    static var ClassRef: JSClassRef? = nil

    static let PR_SIZE = "size"
    static let PR_PATH = "path"
    static let PR_EXISTS = "exists"
    static let PR_IS_DIRECTORY = "isDirectory"

    static let M_LOAD_AS_TEXT = "loadAsText"
    static let M_CREATE_WITH_TEXT = "createWithText"
    static let M_LIST_FILES = "listFiles"
    static let M_DELETE = "delete"
    static let M_MAKE_DIRECTORY = "makeDirectory"

    static func Initialize(_ context: JSContext) {
        FileWrapper.InitializeClass()
        FileWrapper.RegisterClass(context)
    }

    // Register in global object. Just expose the class ref to the world.
    fileprivate static func RegisterClass(_ context: JSContext) {
        let obj: JSObjectRef = JSObjectMake(context.jsGlobalContextRef, FileWrapper.ClassRef, nil);
        JSObjectSetProperty(
            context.jsGlobalContextRef,
            context.globalObject.jsValueRef,
            JSStringCreateWithUTF8CString(ClassName),
            obj,
            JSPropertyAttributes(kJSPropertyAttributeNone),
            nil);
    }

    // JSFile class object contructor
    static let constructorCallback : JSObjectCallAsConstructorCallback = { context, constructor, argc, argv, exception in

        // check parameters. If not suitable, throw an exception.
        if argc < 1 || false==JSValueIsString(context, argv?[0]) {
            if let exception = exception {
                exception.pointee = JSCUtils.Exception(context!, "File constructor just needs one string Argument.")
            }
            // return null on constructor exception. We don't want half-ass baked objects.
            return JSValueMakeNull(context)
        }

        var storage = FileStorage.Bundle
        if argc>1 && JSValueIsNumber(context, argv?[1]) {
            let v = Int(JSValueToNumber(context, argv?[1], nil))
            if v==0 {
                storage = FileStorage.Bundle
            } else if v==1 {
                storage = FileStorage.Documents
            } else if v==2 {
                storage = FileStorage.Remote
            } else {
                print("Undefined storage \(storage)")
            }
        }

        // things looking good. Create an object with the class template.
        // make the js-native attachment.
        let file = File(path: JSCUtils.UnsafeJSStringToString(context!, argv![0]! ), storage: storage )
        return file.associateWithWrapper(context: context!)
    }

    // Javascript File properties: size, path, exists, isDirectory
    static let staticProperties = [

        JSStaticValue(
            name: (PR_SIZE as NSString).utf8String,
            getProperty: { context, object, propertyName, exception in
                let wrappable: File? = Wrappable.from(ref: object)
                guard wrappable != nil else {
                    return JSValueMakeUndefined(context);
                }
                return JSValueMakeNumber(context, wrappable!.fileDelegate!.size )
            },
            setProperty: nil,
            attributes: JSPropertyAttributes(kJSPropertyAttributeDontDelete)),

        JSStaticValue(
            name: (PR_PATH as NSString).utf8String,
            getProperty: { context, object, propertyName, exception in
                let wrappable: File? = Wrappable.from(ref: object)
                guard wrappable != nil else {
                    return JSValueMakeUndefined(context);
                }
                return JSValueMakeString(context, JSCUtils.StringToJSString( wrappable!.fileDelegate!.path ))
            },
            setProperty: nil,
            attributes: JSPropertyAttributes(kJSPropertyAttributeDontDelete)),

        JSStaticValue(
            name: (PR_EXISTS as NSString).utf8String,
            getProperty: { context, object, propertyName, exception in
                let wrappable: File? = Wrappable.from(ref: object)
                guard wrappable != nil else {
                    return JSValueMakeUndefined(context);
                }
                return JSValueMakeBoolean(context, wrappable!.fileDelegate!.exists)
            },
            setProperty: nil,
            attributes: JSPropertyAttributes(kJSPropertyAttributeDontDelete)),

        JSStaticValue(
            name: (PR_IS_DIRECTORY as NSString).utf8String,
            getProperty: { context, object, propertyName, exception in
                let wrappable: File? = Wrappable.from(ref: object)
                guard wrappable != nil else {
                    return JSValueMakeUndefined(context);
                }
                return JSValueMakeBoolean(context, wrappable!.fileDelegate!.isDirectory)
            },
            setProperty: nil,
            attributes: JSPropertyAttributes(kJSPropertyAttributeDontDelete)),

        JSStaticValue(name: nil, getProperty: nil, setProperty: nil, attributes: 0)
    ]

    // Javascript File object prototype functions:
    //   + loadAsText() -> boolean
    //   + createWithText(text: String) -> boolean
    //   + listFiles() -> File[]
    //   + delete() -> boolean
    //   + makeDirectory() -> boolean
    static let staticMethods = [

        JSStaticFunction(
            name: (M_LOAD_AS_TEXT as NSString).utf8String,
            callAsFunction: { context, functionObject, thisObject, argc, argv, exception in
                let wrappable: File? = Wrappable.from(ref: thisObject)
                if let text = wrappable?.loadAsText() {
                    let jsref = JSCUtils.StringToJSString(text)
                    let ret = JSValueMakeString(context, jsref)
                    JSStringRelease(jsref)
                    return ret
                }

                return JSValueMakeUndefined(context)
            },
            attributes: JSPropertyAttributes(kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete)),

        JSStaticFunction(
            name: (M_LIST_FILES as NSString).utf8String,
            callAsFunction: { context, functionObject, thisObject, argc, argv, exception in
                if let file: File = Wrappable.from(ref: thisObject) {
                    if file.fileDelegate!.isDirectory {
                        let files = file.listFiles()
                        var wrappedFiles: [JSValueRef?] = []
                        for newfile in files {
                            wrappedFiles.append(newfile.wrap(in: context!))
                        }

                        return JSObjectMakeArray(context, files.count, UnsafePointer(wrappedFiles), nil)
                    }
                }

                return JSValueMakeUndefined(context)
            },
            attributes: JSPropertyAttributes(kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete)),

        JSStaticFunction(
            name: (M_CREATE_WITH_TEXT as NSString).utf8String,
            callAsFunction: { context, functionObject, thisObject, argc, argv, exception in
                if let file: File = Wrappable.from(ref: thisObject) {
                    if !file.fileDelegate!.isDirectory && argc>0 && JSValueIsString(context, argv![0]) {

                        let ret = file.createWithText( JSCUtils.JSStringToString(context!, argv![0]!))
                        return JSValueMakeBoolean(context, ret)
                    }
                }

                return JSValueMakeBoolean(context, false)
            },
            attributes: JSPropertyAttributes(kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete)),

        JSStaticFunction(
            name: (M_DELETE as NSString).utf8String,
            callAsFunction: { context, functionObject, thisObject, argc, argv, exception in
                if let file: File = Wrappable.from(ref: thisObject) {
                    return JSValueMakeBoolean(context, file.delete())
                }

                return JSValueMakeBoolean(context, false)
            },
            attributes: JSPropertyAttributes(kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete)),


        JSStaticFunction(
            name: (M_MAKE_DIRECTORY as NSString).utf8String,
            callAsFunction: { context, functionObject, thisObject, argc, argv, exception in
                if let file: File = Wrappable.from(ref: thisObject) {
                    return JSValueMakeBoolean(context, file.mkdir())
                }

                return JSValueMakeBoolean(context, false)
            },
            attributes: JSPropertyAttributes(kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete)),

        JSStaticFunction(name: nil, callAsFunction: nil, attributes: 0)
    ]

    // Convert to type. I am getting the wrong type. Get 3 (number) when doing somethign like:
    // console.log(""+file)
    // I expect value 4.
    static let convertToTypeCallback : JSObjectConvertToTypeCallback = { context, object, type, exception in
        if ( type==kJSTypeString ) {
            if let file: File = Wrappable.from(ref: object) {
                return JSCUtils.StringToJSString("File: \(file.fileDelegate!.path)")
            }
        }

        return JSValueMakeNull(context)
    }

    // Finalizer: Free the Wrappable instance.
    static let finalizerCallback : JSObjectFinalizeCallback = { object in

        if let file: File = Wrappable.from(ref: object) {
            file.cleanUp()
        }
    }

    // Create and store the class ref.
    fileprivate static func InitializeClass() {

        var cd = kJSClassDefinitionEmpty

        cd.className = (ClassName as NSString).utf8String
        cd.attributes = JSClassAttributes(kJSClassAttributeNone);
        cd.callAsConstructor = FileWrapper.constructorCallback
        cd.finalize = FileWrapper.finalizerCallback
        cd.convertToType = FileWrapper.convertToTypeCallback
        cd.staticValues = UnsafePointer(FileWrapper.staticProperties)
        cd.staticFunctions = UnsafePointer(FileWrapper.staticMethods)

        FileWrapper.ClassRef = JSClassCreate( &cd )
    }
}
