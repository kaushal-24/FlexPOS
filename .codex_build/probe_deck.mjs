import { pathToFileURL } from "node:url";
const { FileBlob, PresentationFile } = await import(pathToFileURL("C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs").href);
const deck = await PresentationFile.importPptx(await FileBlob.load("C:/Users/Admin/OneDrive/Desktop/flex2/FlexPOS_35_slide_presentation.pptx"));
const slide = deck.slides.getItem(35);
console.log("slide keys", Object.keys(slide));
console.log("shape keys", Object.keys(slide.shapes));
console.log("shape items", slide.shapes.items.map((x,i)=>({i, keys:Object.keys(x), name:x.name, text:x.text?.toString?.(), position:x.position})));
console.log("image keys", Object.keys(slide.images));
console.log("image items", slide.images.items.map((x,i)=>({i, keys:Object.keys(x), name:x.name, position:x.position})));
