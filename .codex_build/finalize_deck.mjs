import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const skillDir = "C:/Users/Admin/.codex/plugins/cache/openai-primary-runtime/presentations/26.1029.11837/skills/presentations";
const workspaceDir = "C:/Users/Admin/.codex/visualizations/2026/10/19/01a153ca-0923-7ce2-aa90-9d43838e2788/flexpos_ppt_build";
const candidatePath = path.join(workspaceDir, "staging/candidate.pptx");
const finalPath = path.join(workspaceDir, "presentation_output/FlexPOS_35_slide_presentation_updated.pptx");
const stagingDir = path.join(workspaceDir, ".codex-finalizer");
await fs.mkdir(stagingDir, { recursive: true });
await fs.mkdir(path.dirname(finalPath), { recursive: true });
await fs.rm(finalPath, { force: true });
const { finalizePresentation } = await import(pathToFileURL(path.join(skillDir, "container_tools/artifact_tool_utils.mjs")).href);
const result = await finalizePresentation({
  workspaceDir,
  candidatePath,
  finalPath,
  pythonExecutable: "C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe",
  integrityValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_layout_geometry.py"),
  layoutArgs: ["--expected-slide-size-emu", "12192000,6858000", "--validate-bullet-geometry", "--validate-heading-fit"],
  requiredNativeTableOwnerSlides: [],
  requiredNativeChartOwnerSlides: [],
  fontPolicy: { basis: "reference", families: ["Georgia", "Arial", "Aptos"], referencePath: path.join(workspaceDir, "source_ref.pptx"), referenceSha256: "61e7b75c4e80d05d98194ddb722b21f7150373e11c89ff37052e58d9bb7d407c" },
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, "FlexPOS_35_slide_presentation_updated.pptx.validation.json"),
});
console.log(JSON.stringify(result));
