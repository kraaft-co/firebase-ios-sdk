//
//  File.swift
//  
//
//  Created by Ryan Wilson on 2022-01-25.
//

import Foundation

private enum Constants {
  static let longType = "type.googleapis.com/google.protobuf.Int64Value"
  static let unsignedLongType = "type.googleapis.com/google.protobuf.UInt64Value"
  static let dateType = "type.googleapis.com/google.protobuf.Timestamp"
}

enum SerializerError: Error {
  // TODO: Add paramters class name and value
  case unsupportedType // (className: String, value: AnyObject)
  case unknownNumberType(charValue: String, number: NSNumber)
  case unimplemented // TODO(wilsonryan): REMOVE
}

class FUNSerializer: NSObject {
  private let dateFormatter: DateFormatter

  override init() {
    dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
  }

  // MARK: - Public APIs

  internal func encode(_ object: Any) throws -> AnyObject {
    if object is NSNull {
      return object as AnyObject
    } else if object is NSNumber {
      return try encodeNumber(object as! NSNumber)
    } else if object is NSString {
      return object as AnyObject
    } else if object is NSDictionary {
      let dict = object as! NSDictionary
      let encoded: NSDictionary = NSDictionary()
      dict.enumerateKeysAndObjects { key, obj, _ in
        // TODO(wilsonryan): Not exact translation
        let anyObj = obj as AnyObject
        let stringKey = key as! String
        let value = try! encode(anyObj)
        encoded.setValue(value, forKey: stringKey)
      }
      return encoded
    } else if object is NSArray {
      let array = object as! NSArray
      let encoded: NSArray = NSArray()
      for item in array {
        let anyItem = item as AnyObject
        let encodedItem = try encode(anyItem)
        encoded.adding(encodedItem)
      }
      return encoded

    } else {
      throw SerializerError.unsupportedType
    }
  }

  internal func decode(_ object: Any) throws -> AnyObject? {
    // Return these types as is. PORTING NOTE: Moved from the bottom of the func for readability.
    if object is NSNumber, object is NSString, object is NSNull {
      return object as AnyObject
    } else if let dict = object as? NSDictionary {
      if dict["@type"] != nil {
        var result: AnyObject? = nil
        do {
          result = try decodeWrappedType(dict)
        } catch {
          return nil
        }

        if result != nil { return result }

        // Treat unknown types as dictionaries, so we don't crash old clients when we add types.
      }

      let decoded = NSMutableDictionary()
      var decodeError: Error? = nil
      dict.enumerateKeysAndObjects { key, obj, stopPointer in
        do {
          let decodedItem = try self.decode(obj)
          decoded[key] = decodedItem
        } catch {
          decodeError = error
          stopPointer.pointee = true
          return
        }
      }

      // Throw the internal error that popped up, if it did.
      if let decodeError = decodeError {
        throw decodeError
      }
      return decoded
    } else if let array = object as? NSArray {
      let result = NSMutableArray(capacity: array.count)
      for obj in array {
        // TODO: Is this data loss? The API is a bit weird.
        if let decoded = try self.decode(obj) {
          result.add(decoded)
        }
      }
      return result
    }

    throw SerializerError.unsupportedType
  }

  // MARK: - Private Helpers

  private func encodeNumber(_ number: NSNumber) throws -> AnyObject {
    // Recover the underlying type of the number, using the method described here:
    // http://stackoverflow.com/questions/2518761/get-type-of-nsnumber
    let cType = number.objCType

    // Type Encoding values taken from
    // https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/
    // Articles/ocrtTypeEncodings.html
    switch cType[0] {
    case CChar("q"):
      // "long long" might be larger than JS supports, so make it a string.
      return ["@type": Constants.longType, "value": "\(number)"] as AnyObject
    case CChar("Q"):
      // "unsigned long long" might be larger than JS supports, so make it a string.
      return ["@type" : Constants.unsignedLongType,
              "value" : "\(number)"] as AnyObject

    case CChar("i"), CChar("s"), CChar("l"), CChar("I"), CChar("S"):
      // If it"s an integer that isn"t too long, so just use the number.
      return number

    case CChar("f"), CChar("d"):
      // It"s a float/double that"s not too large.
      return number

    case CChar("B"), CChar("c"), CChar("C"):
      // Boolean values are weird.
      //
      // On arm64, objCType of a BOOL-valued NSNumber will be "c", even though @encode(BOOL)
      // returns "B". "c" is the same as @encode(signed char). Unfortunately this means that
      // legitimate usage of signed chars is impossible, but this should be rare.
      //
      // Just return Boolean values as-is.
      return number

    default:
      // All documented codes should be handled above, so this shouldn"t happen.
      throw SerializerError.unknownNumberType(charValue: String(cType[0]), number: number)
    }
  }

  private func decodeWrappedType(_ wrapped: NSDictionary) throws -> AnyObject? {
    let type = wrapped["@type"] as! String

    guard let value = wrapped["value"] as? String else {
      return nil
    }

    switch type {
    case Constants.longType:
      let formatter = NumberFormatter()
      guard let n = formatter.number(from: value) else {
        // TODO: Throw FUNInvalidNumberError(value, wrapped);
        return nil
      }

      return n
    case Constants.unsignedLongType:
      // NSNumber formatter doesn't handle unsigned long long, so we have to parse it.
      let str = value.utf8
      // TODO: Port this atrocity
      throw SerializerError.unimplemented
      /*
       const char *str = value.UTF8String;
       char *end = NULL;
       unsigned long long n = strtoull(str, &end, 10);
       if (errno == ERANGE) {
         // This number was actually too big for an unsigned long long.
         if (error != NULL) {
           *error = FUNInvalidNumberError(value, wrapped);
         }
         return nil;
       }
       if (*end) {
         // The whole string wasn't parsed.
         if (error != NULL) {
           *error = FUNInvalidNumberError(value, wrapped);
         }
         return nil;
       }
       return @(n);
       */
    default:
      return nil
    }

  }

}