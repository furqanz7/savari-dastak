import { describe, expect, it } from "vitest";
import {
  readableErrorMessage,
  userFacingError,
} from "./userFacingError";

describe("user-facing errors", () => {
  it("never renders empty or serialized error objects", () => {
    expect(userFacingError(new Error("{}"), "Please try again.")).toBe("Please try again.");
    expect(userFacingError({}, "Please try again.")).toBe("Please try again.");
    expect(userFacingError(new Error('{"code":"internal_error"}'), "Please try again."))
      .toBe("Please try again.");
  });

  it("reads safe nested provider messages", () => {
    expect(readableErrorMessage({ error: { message: "  This request could not be completed.  " } }))
      .toBe("This request could not be completed.");
  });

  it("maps connectivity, session and internal failures to safe copy", () => {
    expect(userFacingError(new TypeError("Failed to fetch"), "Please try again."))
      .toBe("Dastak could not connect. Check your internet connection and try again.");
    expect(userFacingError({ code: "jwt_expired", message: "JWT expired" }, "Please try again."))
      .toBe("Your session has expired. Sign in again to continue.");
    expect(userFacingError(new Error("permission denied for relation auth.users"), "Please try again."))
      .toBe("Please try again.");
  });
});
