import path from "node:path";
const allowed = {
  domain: ["domain"],
  ports: ["domain", "ports"],
  application: ["domain", "ports", "application"],
  infrastructure: ["domain", "ports", "infrastructure"],
  composition: ["domain", "ports", "application", "infrastructure", "composition"],
  app: ["domain", "application", "ports", "composition", "app", "components"],
  components: ["domain", "application", "ports", "app", "components"],
};
const plugin = { rules: { boundaries: {
  meta: { type: "problem", schema: [], messages: { boundary: "{{message}}" } },
  create(context) {
    const file = context.filename.replaceAll("\\", "/");
    const start = file.lastIndexOf("/src/");
    if (start < 0) return {};
    const layer = file.slice(start + 5).split("/")[0];
    function check(node, source) {
      if (typeof source !== "string") return;
      let message;
      if (source.startsWith("@supabase/") && layer !== "infrastructure") message = "Supabase SDK imports belong only in infrastructure/supabase.";
      const resolved = source.startsWith("@/") ? source.slice(2) : source.startsWith(".") ? path.relative(file.slice(0, start + 5), path.resolve(path.dirname(file), source)) : null;
      const target = resolved?.split("/")[0];
      if (target && allowed[layer] && !allowed[layer].includes(target)) message = `${layer} must not depend on ${target}. Use application services and ports.`;
      if (["domain", "ports", "application"].includes(layer) && !resolved) message = "Core layers must remain independent of framework and provider packages.";
      if (message) context.report({ node, messageId: "boundary", data: { message } });
    }
    return {
      ImportDeclaration: node => check(node, node.source.value),
      ExportNamedDeclaration: node => node.source && check(node, node.source.value),
      ExportAllDeclaration: node => check(node, node.source.value),
      ImportExpression: node => check(node, node.source.value),
      CallExpression(node) {
        if (node.callee.name === "require") check(node, node.arguments[0]?.value);
      },
      MemberExpression(node) {
        if (layer === "infrastructure") return;
        if (node.object.type === "Identifier" && node.object.name === "supabase") context.report({ node, messageId: "boundary", data: { message: "Supabase calls belong only in infrastructure/supabase." } });
      },
    };
  },
} } };

export default plugin;
