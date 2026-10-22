import "server-only";
import{userAttentionItems}from"@/domain/user-attention";
import type{RequestClient}from"./server";
export function createUserAttentionAdapter(client:RequestClient){return{async list(){const result=await client.schema("Basic_Carrier_Record").rpc("get_user_attention_items");if(result.error)throw result.error;return userAttentionItems(result.data)}}}
