import { describe, expect, it } from "vitest";
import { foodAvailability, foodCategoryControls, foodCategoryRestaurants, foodDistance, nearestFoodMenus, prepareFoodMenus, searchFood } from "./reimaginedFoodCatalogue";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";

describe("read-only Food projection", () => {
  it("merges loaded search/lookup menus in distance order without mutation, keeping unknowns last", () => {
    const near = foodMenuFixture(); near.restaurant.distanceMeters = 0;
    const far = foodMenuFixture(fixtureId(40)); far.restaurant.distanceMeters = 1250;
    const tied = foodMenuFixture(fixtureId(41)); tied.restaurant.distanceMeters = 1250;
    const unknown = foodMenuFixture(fixtureId(42));
    const original = [unknown, far, near, tied];
    expect(nearestFoodMenus(original)).toEqual([near, far, tied, unknown]);
    expect(original).toEqual([unknown, far, near, tied]);
    expect(foodDistance(near)).toBe("0 m away"); expect(foodDistance(far)).toBe("1.3 km away");
    expect(foodDistance(unknown)).toBe("Distance unavailable");
  });
  it("groups exact labels with branch-scoped category references, without fuzzy matching", () => {
    const first = foodMenuFixture(); const second = foodMenuFixture(fixtureId(40));
    const third = foodMenuFixture(fixtureId(41)); third.categories[0].name = "meals";
    const before = JSON.stringify([first, second, third]);
    const controls = foodCategoryControls([first, second, third]);
    expect(controls.map(group => group.label)).toEqual(["Meals", "meals"]);
    expect(controls[0].members).toEqual([
      { branchId: first.restaurant.branchId, categoryId: first.categories[0].id },
      { branchId: second.restaurant.branchId, categoryId: second.categories[0].id },
    ]);
    expect(foodCategoryRestaurants([first, second, third], controls[0])).toEqual([first, second]);
    expect(JSON.stringify([first, second, third])).toBe(before);
  });
  it("does not advertise empty, blank, inactive or inactive-item-only categories", () => {
    const menu = foodMenuFixture(); const category = menu.categories[0];
    menu.categories.push({ ...category, id: fixtureId(40), name: "Empty", items: [] },
      { ...category, id: fixtureId(41), name: "Hidden", status: "INACTIVE" },
      { ...category, id: fixtureId(42), name: "   " },
      { ...category, id: fixtureId(43), name: "Inactive dishes", items: [{ ...category.items[0], status: "INACTIVE" }] });
    expect(foodCategoryControls([menu]).map(group => group.label)).toEqual(["Meals"]);
  });
  it("retains closed restaurants for browsing but never retargets removed category IDs", () => {
    const menu = foodMenuFixture(); menu.restaurant.isOpen = false;
    const filter = foodCategoryControls([menu])[0];
    expect(foodCategoryRestaurants([menu], filter)).toEqual([menu]);
    const replacement = { ...menu, categories: [{ ...menu.categories[0], id: fixtureId(44) }] };
    expect(foodCategoryRestaurants([replacement], filter)).toEqual([]);
    expect(foodCategoryRestaurants([replacement])).toEqual([replacement]);
    expect(foodCategoryRestaurants([{ ...menu, categories: [{ ...menu.categories[0], name: "Drinks" }] }], filter)).toEqual([]);
  });
  it("searches restaurant, category and dish names without guessing identity", () => {
    const menu = foodMenuFixture(); const menus = prepareFoodMenus([menu]);
    expect(searchFood(menus, "test café")[0].menu.restaurant.branchId).toBe(menu.restaurant.branchId);
    expect(searchFood(menus, "paneer meals")[0].dishes[0].item.id).toBe(menu.categories[0].items[0].id);
    expect(searchFood(menus, "xyz")).toEqual([]); expect(searchFood(menus, " ")).toEqual([]);
    const second = foodMenuFixture(fixtureId(40));
    expect(searchFood(prepareFoodMenus([menu, second]), "paneer")).toHaveLength(2);
  });
  it("filters inactive categories, items and options without changing the source", () => {
    const menu = foodMenuFixture(); const category = menu.categories[0]; const item = category.items[0];
    category.items.push({ ...item, id: fixtureId(41), status: "INACTIVE" });
    menu.categories.push({ ...category, id: fixtureId(42), status: "INACTIVE" });
    item.optionGroups[0].options.push({ ...item.optionGroups[0].options[0], id: fixtureId(43), status: "INACTIVE" });
    const before = JSON.stringify(menu); const result = prepareFoodMenus([menu]);
    expect(result[0].categories).toHaveLength(1); expect(result[0].categories[0].items).toHaveLength(1);
    expect(result[0].categories[0].items[0].optionGroups[0].options).toHaveLength(1); expect(JSON.stringify(menu)).toBe(before);
  });
  it("rejects ambiguous branch, category and dish identities", () => {
    const menu = foodMenuFixture(); expect(() => prepareFoodMenus([menu, menu])).toThrow("duplicate restaurant");
    expect(() => prepareFoodMenus([{ ...menu, categories: [...menu.categories, ...menu.categories] }])).toThrow("duplicate menu category");
    menu.categories[0].items.push(menu.categories[0].items[0]); expect(() => prepareFoodMenus([menu])).toThrow("duplicate dish");
  });
  it("does not equate an open restaurant with guaranteed availability", () => {
    const menu = foodMenuFixture(); expect(foodAvailability(menu)).toContain("checked at checkout");
    menu.restaurant.acceptingOrders = false; expect(foodAvailability(menu)).toBe("Store closed");
    menu.restaurant.isOpen = false; expect(foodAvailability(menu)).toBe("Store closed");
  });
});
