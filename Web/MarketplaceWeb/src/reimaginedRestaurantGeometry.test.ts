import { describe,expect,it } from "vitest";
import { restaurantBevel,restaurantCamera } from "./reimaginedRestaurantGeometry";
describe("restaurant geometry",()=>{
  it("keeps bevel vertices within bounds and normals unit length",()=>{
    const data=restaurantBevel(2,1,.6,.04);const p=data.positions!,n=data.normals!;
    expect(p.length).toBe(6*36*3);expect(data.indices?.length).toBe(6*25*6);
    for(let i=0;i<p.length;i+=3){
      expect(Math.abs(p[i])).toBeLessThanOrEqual(1);expect(Math.abs(p[i+1])).toBeLessThanOrEqual(.5);expect(Math.abs(p[i+2])).toBeLessThanOrEqual(.3);
      expect(Math.hypot(n[i],n[i+1],n[i+2])).toBeCloseTo(1);
    }
    expect(Math.max(...data.indices!)).toBeLessThan(p.length/3);
  });
  it("rejects empty dimensions",()=>expect(()=>restaurantBevel(0,1,1)).toThrow());
  it("centres the phone customer on the staff without crossing the counter",()=>{
    const view=restaurantCamera(true,true);expect(view.position[0]).toBe(0);expect(view.target[0]).toBe(0);
    expect(view.position[2]).toBeLessThan(3.1);expect(view.target[2]).toBe(4.22);
  });
});
