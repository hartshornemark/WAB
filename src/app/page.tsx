import { redirect } from "next/navigation";
import { services } from "@/composition/services";
export default async function Home() { redirect(await (await services()).currentUser() ? "/carriers" : "/login"); }
