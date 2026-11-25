import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
const { FileBlob, PresentationFile } = await import(pathToFileURL("C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs").href);
const candidate = "C:/Users/Admin/OneDrive/Desktop/flex2/flexpos/.codex_build/staging/FlexPOS_35_slide_presentation_updated_candidate.pptx";
const deck = await PresentationFile.importPptx(await FileBlob.load(candidate));
const out = "C:/Users/Admin/OneDrive/Desktop/flex2/flexpos/.codex_build/rendered-updated";
await fs.mkdir(out, {recursive:true});
for (const index of [35,36,37,38,39,40,41,42]) {
  const png = await deck.export({slide: deck.slides.getItem(index), format:"png", scale:1});
  await fs.writeFile(path.join(out, `slide-${index+1}.png`), new Uint8Array(await png.arrayBuffer()));
}
