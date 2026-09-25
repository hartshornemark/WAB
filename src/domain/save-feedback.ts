export type SaveFeedbackState = "editing" | "saving" | "saved";
export type SaveFeedbackSnapshot = {
  state: SaveFeedbackState;
  activeId: string | null;
  busy: boolean;
  error: string;
};

export const initialSaveFeedback: SaveFeedbackSnapshot = {state:"editing",activeId:null,busy:false,error:""};

/** One explicit save at a time. Only a confirmed success may produce a receipt. */
export function createSaveFeedback(notify: (snapshot: SaveFeedbackSnapshot) => void) {
  let snapshot = initialSaveFeedback;
  let afterExit: (() => void) | null = null;
  const update = (patch: Partial<SaveFeedbackSnapshot>) => {
    snapshot = {...snapshot,...patch};
    notify(snapshot);
  };
  const isSaved = () => snapshot.state === "saved";
  return {
    select(id: string) {
      if (snapshot.busy || snapshot.state === "saved") return false;
      update({activeId:id,error:""});
      return true;
    },
    clearSelection() {
      if (!snapshot.busy && !isSaved()) update({activeId:null,error:""});
    },
    async run(action: () => void | Promise<void>) {
      if (snapshot.busy || snapshot.state === "saved") return;
      update({busy:true,state:snapshot.activeId ? "saving" : "editing",error:""});
      try {
        await action();
      } catch {
        afterExit = null;
        update({state:"editing",error:"Unable to save. Your entries are still here; please try again."});
      } finally {
        update({busy:false,...(isSaved() ? {} : {state:"editing" as const,activeId:null})});
      }
    },
    complete(action: () => void) {
      // Automatic checkbox updates and removals keep their existing behaviour.
      // Explicit saves retain the current editor until the user acknowledges it.
      if (!snapshot.activeId) { action(); return; }
      afterExit = action;
      update({state:"saved",error:""});
    },
    exit() {
      if (snapshot.busy || snapshot.state !== "saved") return;
      const action = afterExit;
      afterExit = null;
      update(initialSaveFeedback);
      action?.();
    },
  };
}
