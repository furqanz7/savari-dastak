export * from "../../src/earnings";
import { read } from "./fixture";
export const getAdminRoyaltyPayouts = () => read({ withdrawals: [], hasMore: false });
