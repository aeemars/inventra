import {describe, test, expect} from "@jest/globals";
import {validateOperationId, canonicalJsonStringify, canonicalRequestHash} from "./index";

describe("Server Idempotency and Validation Unit Tests", () => {
  describe("validateOperationId", () => {
    test("accepts valid alphanumeric, dashed, and underscored IDs", () => {
      expect(validateOperationId("OP-123")).toBe("OP-123");
      expect(validateOperationId("op_sale_456")).toBe("op_sale_456");
      expect(validateOperationId("c82c3c54-47cf-4545-985b-b9d9c2a38933")).toBe(
        "c82c3c54-47cf-4545-985b-b9d9c2a38933"
      );
    });

    test("rejects empty or whitespace-only IDs", () => {
      expect(() => validateOperationId("")).toThrow();
      expect(() => validateOperationId("   ")).toThrow();
      expect(() => validateOperationId(null)).toThrow();
      expect(() => validateOperationId(undefined)).toThrow();
    });

    test("rejects path traversal attempts", () => {
      expect(() => validateOperationId("../escape")).toThrow();
      expect(() => validateOperationId("/root/secret")).toThrow();
      expect(() => validateOperationId("op/child")).toThrow();
      expect(() => validateOperationId("op\\child")).toThrow();
    });

    test("rejects strings exceeding 128 characters", () => {
      const longId = "a".repeat(129);
      expect(() => validateOperationId(longId)).toThrow();
      const validMaxId = "a".repeat(128);
      expect(validateOperationId(validMaxId)).toBe(validMaxId);
    });
  });

  describe("canonicalJsonStringify and canonicalRequestHash", () => {
    test("produces identical canonical string regardless of key insertion order", () => {
      const payloadA = {
        shopId: "shop-1",
        items: [{productId: "p1", quantity: 2}],
        total: 500,
        discount: 0,
      };

      const payloadB = {
        discount: 0,
        total: 500,
        shopId: "shop-1",
        items: [{quantity: 2, productId: "p1"}],
      };

      expect(canonicalJsonStringify(payloadA)).toBe(canonicalJsonStringify(payloadB));
      expect(canonicalRequestHash(payloadA)).toBe(canonicalRequestHash(payloadB));
    });

    test("produces different hash when payload values differ", () => {
      const original = {
        shopId: "shop-1",
        productId: "p1",
        quantity: 2,
      };

      const modified = {
        shopId: "shop-1",
        productId: "p1",
        quantity: 50, // Reused operationId with different quantity
      };

      expect(canonicalRequestHash(original)).not.toBe(canonicalRequestHash(modified));
    });
  });
});
