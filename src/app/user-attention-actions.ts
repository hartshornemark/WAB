"use server";
import { userAttentionServices } from "@/composition/services";
export async function listUserAttention(){return (await userAttentionServices()).list();}
