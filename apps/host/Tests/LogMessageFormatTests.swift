import Testing

@testable import CadenzaHost

struct LogMessageFormatTests {
    /// Web traces store their details as JSON text. The list shows the keys in order, with booleans and null readable.
    @Test func aJSONObjectReadsAsOneLineInKeyOrder() {
        #expect(
            LogMessageFormat.summary(#"{"transport":"ble","attempt":2,"ok":true,"error":null}"#)
                == "attempt: 2  error: null  ok: true  transport: ble")
        #expect(LogMessageFormat.summary(#"{"detail":{"b":1,"a":2}}"#) == #"detail: {"a":2,"b":1}"#)
    }

    @Test func textThatIsNotAJSONObjectIsShownAsWritten() {
        #expect(LogMessageFormat.summary("Remote connection opened") == "Remote connection opened")
        #expect(LogMessageFormat.summary("{not json") == "{not json")
        #expect(LogMessageFormat.pretty("Remote connection opened") == nil)
    }

    @Test func thePrettyFormKeepsKeysInOrderForTheDetailsPage() throws {
        let pretty = try #require(LogMessageFormat.pretty(#"{"b":1,"a":"x"}"#))
        #expect(pretty == "{\n  \"a\" : \"x\",\n  \"b\" : 1\n}")
    }
}
