import { test, expect } from "@playwright/test";

test("a released A350 with no published edition opens its board and load tray before AUTOLOAD", async ({ page }) => {
  test.skip(!process.env.E2E_EMAIL || !process.env.E2E_PASSWORD || !process.env.E2E_DRAFT_A350_PATH,
    "Requires an assigned test account and an existing released A350 flight with no published load-plan edition.");
  await page.goto("/login");
  await page.getByLabel("Email").fill(process.env.E2E_EMAIL!);
  await page.getByLabel("Password", { exact: true }).fill(process.env.E2E_PASSWORD!);
  await page.getByRole("button", { name: "Sign in →" }).click();
  await expect(page).not.toHaveURL(/\/login$/);
  await page.goto(`${process.env.E2E_DRAFT_A350_PATH!.split("#")[0]}#load-plan`);
  const plan = page.locator("#load-plan");
  await expect(plan).toHaveAttribute("open", "");
  await expect(plan.getByText("NO PUBLISHED EDITION", { exact: true })).toBeVisible();
  await expect(plan.getByRole("heading", { name: "Compact physical hold layout" })).toBeVisible();
  await expect(plan.getByRole("heading", { name: "Load Tray", exact: true })).toBeVisible();
  await expect(plan.getByRole("button", { name: "AUTOLOAD", exact: true })).toBeEnabled();
  await expect(plan.getByRole("button", { name: "PUBLISH EDN 1", exact: true })).toBeDisabled();
  await page.reload();
  await expect(plan.getByRole("heading", { name: "Compact physical hold layout" })).toBeVisible();
  await expect(plan.getByRole("button", { name: "AUTOLOAD", exact: true })).toBeEnabled();
  // Read-only regression: opening and reloading must not create an edition.
  await expect(plan.getByText("NO PUBLISHED EDITION", { exact: true })).toBeVisible();
});
