import { describe, expect, it } from "vitest";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { foodSelection, sameFoodOptions } from "./reimaginedFoodSelection";
import { prepareFoodMenus } from "./reimaginedFoodCatalogue";

describe("Food selections", () => {
  it("rejects missing, unknown and duplicate choices and prices only exact options", () => {
    const item = foodMenuFixture().categories[0].items[0]; const id = item.optionGroups[0].options[0].id;
    expect(foodSelection(item, []).valid).toBe(false);
    expect(foodSelection(item, [id, id]).valid).toBe(false);
    expect(foodSelection(item, ["unknown"]).valid).toBe(false);
    expect(foodSelection(item, [id])).toMatchObject({ valid: true, pricePaise: 18000 });
    expect(sameFoodOptions(["a", "b"], ["b", "a"])).toBe(true);
    expect(sameFoodOptions(["a"], ["b"])).toBe(false);
  });
  it("enforces multiple-choice limits and distinguishes option combinations", () => {
    const item = foodMenuFixture().categories[0].items[0];
    item.optionGroups[0] = { ...item.optionGroups[0], selectionType: "MULTIPLE", minimumSelections: 0, maximumSelections: 1, options: [item.optionGroups[0].options[0], { ...item.optionGroups[0].options[0], id: "second", priceDeltaPaise: 1000 }] };
    const first = item.optionGroups[0].options[0].id;
    expect(foodSelection(item, []).valid).toBe(true);
    expect(foodSelection(item, [first, "second"]).valid).toBe(false);
    expect(foodSelection(item, ["second"]).pricePaise).toBe(16000);
  });
  it("rejects ambiguous option identities and invalid group bounds", () => {
    const menu = foodMenuFixture(); const group = menu.categories[0].items[0].optionGroups[0];
    group.options.push({ ...group.options[0] });
    expect(() => prepareFoodMenus([menu])).toThrow("duplicate option");
    group.options.pop(); group.maximumSelections = 2;
    expect(() => prepareFoodMenus([menu])).toThrow("ambiguous option");
  });
});
