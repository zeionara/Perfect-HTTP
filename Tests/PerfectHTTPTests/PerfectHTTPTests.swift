import XCTest
import PerfectNet
import PerfectLib
@testable import PerfectHTTP

#if os(Linux)
	import SwiftGlibc
#endif

// random from 1 to upper, inclusive
func _rand(to upper: Int32) -> Int32 {
	#if os(OSX)
		return Int32(arc4random_uniform(UInt32(upper-1))) + 1
	#else
		return (SwiftGlibc.rand() % Int32(upper-1)) + 1
	#endif
}

class ShimHTTPRequest: HTTPRequest {
	var method = HTTPMethod.get
	var path = "/"
	var queryParams = [(String, String)]()
	var protocolVersion = (1, 1)
	var remoteAddress = (host: "127.0.0.1", port: 8000 as UInt16)
	var serverAddress = (host: "127.0.0.1", port: 8282 as UInt16)
	var serverName = "my_server"
	var documentRoot = "./webroot"
	var connection = NetTCP()
	var urlVariables = [String:String]()
	func header(_ named: HTTPRequestHeader.Name) -> String? { return nil }
	func addHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	func setHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	var headers = AnyIterator<(HTTPRequestHeader.Name, String)> { return nil }
	var postParams = [(String, String)]()
	var postBodyBytes: [UInt8]? = nil
	var postBodyString: String? = nil
	var postFileUploads: [MimeReader.BodySpec]? = nil
}

class ShimHTTPResponse: HTTPResponse {
	var request: HTTPRequest = ShimHTTPRequest()
	var status: HTTPResponseStatus = .ok
	var isStreaming = false
	var bodyBytes = [UInt8]()
	func header(_ named: HTTPResponseHeader.Name) -> String? { return nil }
	func addHeader(_ named: HTTPResponseHeader.Name, value: String) {}
	func setHeader(_ named: HTTPResponseHeader.Name, value: String) {}
	var headers = AnyIterator<(HTTPResponseHeader.Name, String)> { return nil }
	func addCookie(_: PerfectHTTP.HTTPCookie) {}
	func appendBody(bytes: [UInt8]) {}
	func appendBody(string: String) {}
	func setBody(json: [String:Any]) throws {}
	func push(callback: @escaping (Bool) -> ()) {}
	func completed() {}
}

class PerfectHTTPTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
	}
	
	func testMimeReaderSimple() {
		let boundary = "--6"
		var testData = Array<Dictionary<String, String>>()
		let numTestFields = 2
		for idx in 0..<numTestFields {
			var testDic = Dictionary<String, String>()
			testDic["name"] = "test_field_\(idx)"
			var testValue = ""
			for _ in 1...4 {
				testValue.append("O")
			}
			testDic["value"] = testValue
			testData.append(testDic)
		}
		let file = File("/tmp/mimeReaderTest.txt")
		do {
			try file.open(.truncate)
			for testDic in testData {
				let _ = try file.write(string: "--" + boundary + "\r\n")
				let testName = testDic["name"]!
				let testValue = testDic["value"]!
				let _ = try file.write(string: "Content-Disposition: form-data; name=\"\(testName)\"; filename=\"\(testName).txt\"\r\n")
				let _ = try file.write(string: "Content-Type: text/plain\r\n\r\n")
				let _ = try file.write(string: testValue)
				let _ = try file.write(string: "\r\n")
			}
			let _ = try file.write(string: "--" + boundary + "--")
			for num in 1...1 {
				file.close()
				try file.open()
				let mimeReader = MimeReader("multipart/form-data; boundary=" + boundary)
				XCTAssertEqual(mimeReader.boundary, "--" + boundary)
				var bytes = try file.readSomeBytes(count: num)
				while bytes.count > 0 {
					mimeReader.addToBuffer(bytes: bytes)
					bytes = try file.readSomeBytes(count: num)
				}
				XCTAssertEqual(mimeReader.bodySpecs.count, testData.count)
				var idx = 0
				for body in mimeReader.bodySpecs {
					let testDic = testData[idx]
					idx += 1
					XCTAssertEqual(testDic["name"]!, body.fieldName)
					let file = File(body.tmpFileName)
					try file.open()
					let contents = try file.readSomeBytes(count: file.size)
					file.close()
					let decoded = UTF8Encoding.encode(bytes: contents)
					let v = testDic["value"]!
					XCTAssertEqual(v, decoded)
					body.cleanup()
				}
			}
			file.close()
			file.delete()
		} catch let e {
			print("Exception while testing MimeReader: \(e)")
		}
	}

	func testMimeReader() {
		
		let boundary = "----9051914041544843365972754266"
		
		var testData = [[String:String]]()
		let numTestFields = 1 + _rand(to: 100)
		
		for idx in 0..<numTestFields {
			var testDic = Dictionary<String, String>()
			
			testDic["name"] = "test_field_\(idx)"
			
			let isFile = _rand(to: 3) == 2
			if isFile {
				var testValue = ""
				for _ in 1..<_rand(to: 1000) {
					testValue.append("O")
				}
				testDic["value"] = testValue
				testDic["file"] = "1"
			} else {
				var testValue = ""
				for _ in 0..<_rand(to: 1000) {
					testValue.append("O")
				}
				testDic["value"] = testValue
			}
			
			testData.append(testDic)
		}
		
		let file = File("/tmp/mimeReaderTest.txt")
		do {
			try file.open(.truncate)
			for testDic in testData {
				try file.write(string: "--" + boundary + "\r\n")
				let testName = testDic["name"]!
				let testValue = testDic["value"]!
				let isFile = testDic["file"]
				if let _ = isFile {
					try file.write(string: "Content-Disposition: form-data; name=\"\(testName)\"; filename=\"\(testName).txt\"\r\n")
					try file.write(string: "Content-Type: text/plain\r\n\r\n")
					try file.write(string: testValue)
					try file.write(string: "\r\n")
				} else {
					try file.write(string: "Content-Disposition: form-data; name=\"\(testName)\"\r\n\r\n")
					try file.write(string: testValue)
					try file.write(string: "\r\n")
				}
			}
			
			try file.write(string: "--" + boundary + "--")
			
			for num in 1...2048 {
				
				file.close()
				try file.open()
				
				//print("Test run: \(num) bytes with \(numTestFields) fields")
				
				let mimeReader = MimeReader("multipart/form-data; boundary=" + boundary)
				
				XCTAssertEqual(mimeReader.boundary, "--" + boundary)
				
				var bytes = try file.readSomeBytes(count: num)
				while bytes.count > 0 {
					mimeReader.addToBuffer(bytes: bytes)
					bytes = try file.readSomeBytes(count: num)
				}
				
				XCTAssertEqual(mimeReader.bodySpecs.count, testData.count)
				
				var idx = 0
				for body in mimeReader.bodySpecs {
					
					let testDic = testData[idx]
					idx += 1
					XCTAssertEqual(testDic["name"]!, body.fieldName)
					if let _ = testDic["file"] {
						
						let file = File(body.tmpFileName)
						try file.open()
						let contents = try file.readSomeBytes(count: file.size)
						file.close()
						
						let decoded = UTF8Encoding.encode(bytes: contents)
						let v = testDic["value"]!
						XCTAssertEqual(v, decoded)
					} else {
						XCTAssertEqual(testDic["value"]!, body.fieldValue)
					}
					
					body.cleanup()
				}
			}
			
			file.close()
			file.delete()
			
		} catch let e {
			XCTAssert(false, "\(e)")
		}
	}
	
	func testRoutingFound1() {
		let uri = "/foo/bar/baz"
		var r = Routes()
		r.add(method: .get, uri: uri, handler: { _, _ in })
		let req = ShimHTTPRequest()
		let fnd = r.navigator.findHandler(uri: uri, webRequest: req)
		XCTAssert(fnd != nil)
	}
	
	func testRoutingFound2() {
		let uri = "/foo/bar/baz"
		var r = Routes()
		r.add(uri: uri, handler: { _, _ in })
		let req = ShimHTTPRequest()
		do {
			let fnd = r.navigator.findHandler(uri: uri, webRequest: req)
			XCTAssert(fnd != nil)
		}
		req.method = .post
		do {
			let fnd = r.navigator.findHandler(uri: uri, webRequest: req)
			XCTAssert(fnd != nil)
		}
	}
	
	func testRoutingNotFound() {
		let uri = "/foo/bar/baz"
		var r = Routes()
		r.add(method: .get, uri: uri, handler: { _, _ in })
		let req = ShimHTTPRequest()
		let fnd = r.navigator.findHandler(uri: uri+"z", webRequest: req)
		XCTAssert(fnd == nil)
	}
	
	func testRoutingWild() {
		let uri = "/foo/*/baz/*"		
		var r = Routes()
		r.add(method: .get, uri: uri, handler: { _, _ in })
		let req = ShimHTTPRequest()
		let fnd = r.navigator.findHandler(uri: "/foo/bar/baz/bum", webRequest: req)
		XCTAssert(fnd != nil)
	}
	
	func testRoutingVars() {
		let uri = "/foo/{bar}/baz/{bum}"
		var r = Routes()
		r.add(method: .get, uri: uri, handler: { _, _ in })
		let req = ShimHTTPRequest()
		let fnd = r.navigator.findHandler(uri: "/foo/1/baz/2", webRequest: req)
		XCTAssert(fnd != nil)
		XCTAssert(req.urlVariables["bar"] == "1")
		XCTAssert(req.urlVariables["bum"] == "2")
	}
	
	func testRoutingTrailingWild1() {
		let uri = "/foo/**"
		var r = Routes()
		r.add(method: .get, uri: uri, handler: { _, _ in })
		let req = ShimHTTPRequest()
		do {
			let fnd = r.navigator.findHandler(uri: "/foo/bar/baz/bum", webRequest: req)
			XCTAssert(fnd != nil)
			XCTAssert(req.urlVariables[routeTrailingWildcardKey] == "/bar/baz/bum")
		}
		
		do {
			let fnd = r.navigator.findHandler(uri: "/foo/bar", webRequest: req)
			XCTAssert(fnd != nil)
		}
		
		do {
			let fnd = r.navigator.findHandler(uri: "/foo/", webRequest: req)
			XCTAssert(fnd != nil)
		}
		
		do {
			let fnd = r.navigator.findHandler(uri: "/fooo0/", webRequest: req)
			XCTAssert(fnd == nil)
		}
	}
	
	func testRoutingTrailingWild2() {
		let uri = "**"
		var r = Routes()
		r.add(method: .get, uri: uri, handler: { _, _ in })
		let req = ShimHTTPRequest()
		do {
			let fnd = r.navigator.findHandler(uri: "/foo/bar/baz/bum", webRequest: req)
			XCTAssert(fnd != nil)
			XCTAssert(req.urlVariables[routeTrailingWildcardKey] == "/foo/bar/baz/bum")
		}
		
		do {
			let fnd = r.navigator.findHandler(uri: "/foo/bar", webRequest: req)
			XCTAssert(fnd != nil)
		}
		
		do {
			let fnd = r.navigator.findHandler(uri: "/foo/", webRequest: req)
			XCTAssert(fnd != nil)
		}
	}
	
	func testRoutingAddPerformance() {
		var r = Routes()
		self.measure {
			for i in 0..<10000 {
				r.add(method: .get, uri: "/foo/\(i)/baz", handler: { _, _ in })
			}
		}
	}
	
	func testRoutingFindPerformance() {
		var r = Routes()
		for i in 0..<10000 {
			r.add(method: .get, uri: "/foo/\(i)/baz", handler: { _, _ in })
		}
		let req = ShimHTTPRequest()
		let navigator = r.navigator
		self.measure {
			for i in 0..<10000 {
				guard let _ = navigator.findHandler(uri: "/foo/\(i)/baz", webRequest: req) else {
					XCTAssert(false, "Failed to find route")
					break
				}
			}
		}
	}
	
	func testFormatDate() {
		let dateThen = 0.0
		let formatStr = "%a, %d-%b-%Y %T GMT"
		if let result = dateThen.formatDate(format: formatStr){
			XCTAssertEqual(result, "Thu, 01-Jan-1970 00:00:00 GMT")
		} else {
			XCTAssert(false, "Bad date format")
		}
	}

    static var allTests : [(String, (PerfectHTTPTests) -> () throws -> Void)] {
        return [
			("testMimeReader", testMimeReader),
			("testMimeReaderSimple", testMimeReaderSimple),
			("testRoutingFound1", testRoutingFound1),
			("testRoutingFound2", testRoutingFound2),
			("testRoutingNotFound", testRoutingNotFound),
			("testRoutingWild", testRoutingWild),
			("testRoutingVars", testRoutingVars),
			("testRoutingAddPerformance", testRoutingAddPerformance),
			("testRoutingFindPerformance", testRoutingFindPerformance),
			("testRoutingTrailingWild1", testRoutingTrailingWild1),
			("testRoutingTrailingWild2", testRoutingTrailingWild2),
			("testFormatDate", testFormatDate)
        ]
    }
}
