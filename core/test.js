const fs = require("fs");

const raw = fs.readFileSync("./build/Ledger.sol/Ledger.json");
const json = JSON.parse(raw);
const abi = json.abi;
const ast = json.ast;

for (const func of abi) {
  if (func.type === "constructor") continue;
  if (!(func.stateMutability === "view" || func.stateMutability === "pure")) {
    console.error("ERROR: Ledger has state-modifying functions.");
    console.info(func);
    process.exit(1);
  }
}

const ledger = ast.nodes[ast.nodes.length - 1];
if (ledger.nodeType !== "ContractDefinition" || ledger.name !== "Ledger") {
  console.error("ERROR: Malformed Ledger AST");
  process.exit(1);
}

for (const node of ledger.nodes) {
  if (node.kind !== "function") continue;
  if (!(node.stateMutability === "view" || node.stateMutability === "pure")) {
    console.error("ERROR: Ledger has state-modifying functions.");
    console.info(node);
    process.exit(1);
  }
}
