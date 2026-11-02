import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SKILL_DIR = 'C:/Users/Admin/.codex/plugins/cache/openai-primary-runtime/presentations/26.1025.11240/skills/presentations';
const workspaceDir = 'C:/Users/Admin/.codex/visualizations/2026/10/19/01a153ca-0923-7ce2-aa90-9d43838e2788/flexpos-presentation-finalize';
const candidatePath = path.join(workspaceDir, 'FlexPOS_35_slide_presentation.draft.pptx');
// Publish first in the local visualization workspace so the finalizer can use
// its validation hard-link step; the verified bytes are copied into the
// workspace deliverable directory afterward.
const finalPath = path.join(workspaceDir, 'presentation_output', 'FlexPOS_35_slide_presentation.pptx');
const stagingDir = path.join(workspaceDir, '.codex-finalizer');

const { finalizePresentation } = await import(pathToFileURL(path.join(SKILL_DIR, 'container_tools', 'artifact_tool_utils.mjs')).href);

const result = await finalizePresentation({
  explicitTotalSlideCount: 35,
  workspaceDir,
  candidatePath,
  finalPath,
  pythonExecutable: 'C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
  integrityValidatorPath: path.join(SKILL_DIR, 'container_tools', 'inspect_presentation_package_integrity.py'),
  layoutValidatorPath: path.join(SKILL_DIR, 'container_tools', 'inspect_presentation_layout_geometry.py'),
  layoutArgs: ['--expected-slide-size-emu', '12192000,6858000', '--validate-bullet-geometry', '--validate-heading-fit'],
  requiredNativeTableOwnerSlides: [],
  fontPolicy: { basis: 'design', families: ['Georgia', 'Arial'] },
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, 'FlexPOS_35_slide_presentation.validation.json'),
});
console.log(JSON.stringify(result));
