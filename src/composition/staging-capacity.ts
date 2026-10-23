import "server-only";
import { createStagingCapacityEndpoint } from "@/infrastructure/capacity/staging-endpoint";
export const stagingCapacityEndpoint = createStagingCapacityEndpoint();
