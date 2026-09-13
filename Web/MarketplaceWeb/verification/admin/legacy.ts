export * from "../../src/admin";
import { id, read, timestamp as at } from "./fixture";
export const getMerchantApplications = () => read([{ applicationId: id(70), status: "pending", businessName: "New Market Cafe", businessAddress: "Central Market, Vaniyambadi", legalName: "New Market Cafe", applicantName: "Test Applicant", applicantPhone: "•••• 0987", merchantType: "RESTAURANT_CAFE", serviceZoneName: "Vaniyambadi Central", submittedAt: at, latitude: 12.67, longitude: 78.61, evidenceObjectPath: "blocked-fixture" }], []);
export const getPartnerApplications = () => read([], []);
export const getAdminOrderPage = () => read({ orders: [], hasMore: false });
export const getOwnerOperations = () => read({ summary: { totalExceptions: 0, stalledOrders: 0 }, exceptions: [] });
export const getOwnerExceptionPage = () => read({ exceptions: [], hasMore: false });
