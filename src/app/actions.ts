"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { services } from "@/composition/services";
export async function signIn(_state: { error: string }, form: FormData) {
  const email = form.get("email");
  const password = form.get("password");
  if (typeof email !== "string" || typeof password !== "string") return { error: "Enter your email and password." };
  try { await (await services()).signIn(email, password); }
  catch { return { error: "Unable to sign in. Check your details and try again." }; }
  revalidatePath("/", "layout");
  redirect("/carriers");
}
export async function signOut() {
  await (await services()).signOut();
  revalidatePath("/", "layout");
  redirect("/login");
}
