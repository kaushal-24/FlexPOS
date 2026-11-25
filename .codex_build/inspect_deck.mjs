import fs from "node:fs/promises";
import { pathToFileURL } from "node:url";
const { FileBlob, PresentationFile } = await import(pathToFileURL("C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs").href);

const input = "C:/Users/Admin/OneDrive/Desktop/flex2/FlexPOS_35_slide_presentation.pptx";
const outDir = "C:/Users/Admin/OneDrive/Desktop/flex2/flexpos/.codex_build";
await fs.mkdir(outDir, { recursive: true });
const deck = await PresentationFile.importPptx(await FileBlob.load(input));
const info = await deck.inspect({ kind: "slide,textbox,shape,image,table,chart,notes,layout", maxChars: 120000 });
await fs.writeFile(`${outDir}/deck-inspect.ndjson`, info.ndjson ?? JSON.stringify(info));
const montage = await deck.export({ format: "webp", montage: true, scale: 1 });
await fs.writeFile(`${outDir}/deck-montage.webp`, new Uint8Array(await montage.arrayBuffer()));
const meta = await deck.inspect({ kind: "slide,layout", maxChars: 20000 });
await fs.writeFile(`${outDir}/deck-meta.ndjson`, meta.ndjson ?? JSON.stringify(meta));
