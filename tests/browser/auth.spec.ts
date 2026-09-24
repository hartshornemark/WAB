import { test, expect } from "@playwright/test";
test("signed-out routes redirect and sign-in form is usable", async ({ page }) => {
  await page.goto("/carriers");
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole("heading", { name: "Sign in to your workspace" })).toBeVisible();
  await expect(page.getByLabel("Email")).toBeVisible();
  await expect(page.getByLabel("Password", { exact: true })).toHaveAttribute("type", "password");
  await page.goto("/carrier/ZZ");
  await expect(page).toHaveURL(/\/login$/);
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
test("real assigned account signs in, selects a carrier, and signs out", async ({ page }) => {
  test.skip(!process.env.E2E_EMAIL || !process.env.E2E_PASSWORD, "Requires an existing assigned test account in local environment.");
  await page.goto("/login");
  await page.getByLabel("Email").fill(process.env.E2E_EMAIL!);
  await page.getByLabel("Password", { exact: true }).fill(process.env.E2E_PASSWORD!);
  await page.getByRole("button", { name: "Sign in →" }).click();
  await expect(page).toHaveURL(/\/carriers$/);
  await page.locator(".carrier-card").first().click();
  await expect(page.getByText("Carrier selected", { exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByText("Carrier selected", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/login$/);
  await page.goto("/carriers");
  await expect(page).toHaveURL(/\/login$/);
});
