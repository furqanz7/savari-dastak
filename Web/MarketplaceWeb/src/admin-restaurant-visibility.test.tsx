// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AdminMerchantGovernancePanel } from "./AdminMerchantGovernancePanel";
import { getV1AdminMerchantGovernancePage, setV1AdminRestaurantCustomerVisibility, type V1AdminMerchantGovernanceRow } from "./dastakV1";
import { resetAdminMutationStateForTests } from "./adminPrivilegedMutation";
vi.mock("./dastakV1", () => ({ getV1AdminMerchantGovernancePage: vi.fn(), setV1AdminRestaurantCustomerVisibility: vi.fn(), setV1AdminMerchantOrganizationStatus: vi.fn(), setV1AdminMerchantBranchStatus: vi.fn(), correctV1AdminMerchantBranchDetails: vi.fn() }));
vi.mock("./adminRefresh", () => ({ useAdminWorkspaceRefresh: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const auth={accessToken:"test",supabaseUrl:"https://example.invalid",publishableKey:"public"};
const id="88888888-8888-4888-8888-888888888888";
const row:V1AdminMerchantGovernanceRow={organization:{id,displayName:"Craft",legalName:"Craft Foods",merchantType:"RESTAURANT_CAFE",status:"ACTIVE",version:1,activeNonTerminalFulfilmentCount:0,activePickupReturnWorkCount:0},
 branch:{id,displayName:"Craft Central",status:"ACTIVE",version:3,normalizedAddress:{},serviceZone:{},capacityLimit:12,customerListingVisible:true,operationalState:{isOpen:false,acceptingOrders:false},activeNonTerminalFulfilmentCount:0,activePickupReturnWorkCount:0},updatedAt:"2026-10-08T00:00:00Z"};
let root:Root;let host:HTMLDivElement;
async function mount(visible:boolean|undefined){
 vi.mocked(getV1AdminMerchantGovernancePage).mockResolvedValue({merchants:[{...row,branch:{...row.branch,customerListingVisible:visible}}],serviceZones:[],hasMore:false});
 host=document.createElement("div");document.body.append(host);root=createRoot(host);
 await act(async()=>{root.render(<AdminMerchantGovernancePanel auth={auth}/>);});
 await act(async()=>{vi.advanceTimersByTime(250);});
}
function button(text:string){const found=[...host.querySelectorAll("button")].find(b=>b.textContent?.trim()===text);expect(found,`button ${text}`).toBeDefined();return found!;}
beforeEach(()=>{vi.useFakeTimers();vi.clearAllMocks();resetAdminMutationStateForTests();vi.mocked(setV1AdminRestaurantCustomerVisibility).mockResolvedValue({});});
afterEach(()=>{if(root)act(()=>root.unmount());host?.remove();vi.useRealTimers();});
describe("Admin Restaurant Customer visibility",()=>{
 it("requires typed branch confirmation and sends only reviewed removal intent",async()=>{
  await mount(true);expect(host.textContent).toContain("Closed · Not accepting");
  act(()=>button("Remove from Customer").click());
  expect(button("Confirm removal").disabled).toBe(true);
  const input=host.querySelector<HTMLInputElement>(".admin-confirmation-match input")!;
  await act(async()=>{Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,"value")?.set?.call(input,"Craft Central");input.dispatchEvent(new Event("input",{bubbles:true}));});
  expect(button("Confirm removal").disabled).toBe(false);
  await act(async()=>button("Confirm removal").click());
  expect(setV1AdminRestaurantCustomerVisibility).toHaveBeenCalledWith(expect.objectContaining({branchId:id,visible:false,expectedVersion:3,reason:"Merchant requested",idempotencyKey:expect.any(String)}));
 });
 it("restores visibility without promising to reopen the closed store",async()=>{
  await mount(false);expect(host.textContent).toContain("Removed by Admin");
  act(()=>button("Restore to Customer").click());expect(host.textContent).toContain("Restoration does not reopen a closed store");
  await act(async()=>button("Confirm restoration").click());
  expect(setV1AdminRestaurantCustomerVisibility).toHaveBeenCalledWith(expect.objectContaining({visible:true,expectedVersion:3}));
 });
 it("fails closed when the deployed backend has no visibility projection",async()=>{
  await mount(undefined);expect(button("Remove from Customer").disabled).toBe(true);expect(host.textContent).toContain("Visibility control unavailable");
  expect(setV1AdminRestaurantCustomerVisibility).not.toHaveBeenCalled();
 });
});
