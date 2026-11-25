import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const { FileBlob, PresentationFile } = await import(pathToFileURL(
  "C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs",
).href);

const workspaceDir = "C:/Users/Admin/OneDrive/Desktop/flex2/flexpos";
const inputPath = "C:/Users/Admin/OneDrive/Desktop/flex2/FlexPOS_35_slide_presentation.pptx";
const buildDir = path.join(workspaceDir, ".codex_build");
const stagingDir = path.join(buildDir, "staging");
const outputDir = path.join(workspaceDir, "presentation_output");
const candidatePath = path.join(stagingDir, "FlexPOS_35_slide_presentation_updated_candidate.pptx");
const finalPath = path.join(outputDir, "FlexPOS_35_slide_presentation_updated.pptx");

await fs.mkdir(stagingDir, { recursive: true });
await fs.mkdir(outputDir, { recursive: true });

const deck = await PresentationFile.importPptx(await FileBlob.load(inputPath));
const localAsset = (name) => path.join(workspaceDir, "presentation_assets", name);
const desktopScreenshot = "C:/Users/Admin/AppData/Local/Temp/codex-clipboard-3141de0f-6eed-4d65-ac59-7e7f673af1f7.png";

async function replaceSlideImage(slide, filePath, alt, frame = null, fit = null) {
  const image = slide.images.items[0];
  if (!image) throw new Error(`Expected an image on slide for ${alt}`);
  const oldFrame = image.frame;
  const oldCrop = image.crop;
  const oldFit = image.fit;
  const bytes = await fs.readFile(filePath);
  await image.replace({
    blob: bytes,
    contentType: "image/png",
    alt,
    ...(fit ? { fit } : oldFit ? { fit: oldFit } : {}),
  });
  image.frame = frame ?? oldFrame;
  if (oldCrop) image.crop = oldCrop;
  return image;
}

function setContent(slide, { page, title, leftStatement, bullets, imagePath, imageAlt, imageFrame, imageFit }) {
  const shapes = slide.shapes.items;
  // Image-and-copy template: header/footer, title, left statement, right bullets.
  shapes[2].text = "FLEXPOS · ENTERPRISE POS";
  shapes[3].text = String(page).padStart(2, "0");
  shapes[4].text = title;
  if (leftStatement !== undefined) shapes[7].text = leftStatement;
  shapes[8].text = bullets;
  return replaceSlideImage(slide, imagePath, imageAlt, imageFrame, imageFit);
}

async function appendImageSlide({ title, leftStatement, bullets, imagePath, imageAlt }) {
  const source = deck.slides.getItem(15); // Feature modules image-and-copy rhythm.
  const slide = source.duplicate();
  slide.moveTo(deck.slides.items.length - 2); // Keep the existing Thank You slide last.
  const page = deck.slides.items.length - 1;
  await setContent(slide, {
    page,
    title,
    leftStatement,
    bullets,
    imagePath,
    imageAlt,
  });
  return slide;
}

await appendImageSlide({
  title: "WAREHOUSES AND STOCK BY LOCATION",
  leftStatement: "Warehouse records connect each SKU to a branch, a balance and an auditable movement history.",
  bullets: "◆  Create, edit, delete and restore warehouses with inventory permissions.\n\n◆  Stock balances identify the warehouse that can fulfill a sale.\n\n◆  Transfers, adjustments and stocktakes preserve location-level history.",
  imagePath: localAsset("flexpos-inventory.png"),
  imageAlt: "FlexPOS inventory screen showing warehouse-aware stock operations",
});

await appendImageSlide({
  title: "STAFF, ROLES AND ACCESS CONTROL",
  leftStatement: "User access combines membership, branch scope and permission checks so each staff member sees the right workspace.",
  bullets: "◆  Staff accounts carry role, branch assignment and active status.\n\n◆  Admins can create accounts, edit access, remove access and review audit history.\n\n◆  Cashiers see sellable stock; inventory controls follow the assigned role.",
  imagePath: localAsset("flexpos-modules.png"),
  imageAlt: "FlexPOS module navigation and permission-aware workspace",
});

await appendImageSlide({
  title: "INDUSTRY AND ENTERPRISE OPERATIONS",
  leftStatement: "The platform carries a shared operating model while keeping industry-specific workflows configurable.",
  bullets: "◆  Industry workflows cover restaurant, repair, wholesale, grocery, fashion, pharmacy, salon, manufacturing and rental use cases.\n\n◆  Feature entitlements control which modules appear in navigation.\n\n◆  Enterprise operations add devices, integrations, audit and governance controls.",
  imagePath: localAsset("flexpos-dashboard.png"),
  imageAlt: "FlexPOS dashboard for multi-module business operations",
});

await appendImageSlide({
  title: "HARDWARE, INTEGRATIONS AND MONITORING",
  leftStatement: "Online hardware and provider integrations stay explicit so operators can see what is ready at the counter.",
  bullets: "◆  Camera and keyboard barcode scanning connect directly to POS search.\n\n◆  Device, printer and payment-provider status remain visible to operators.\n\n◆  Production release checks still cover physical scanners, printers and provider credentials.",
  imagePath: desktopScreenshot,
  imageAlt: "FlexPOS desktop POS workspace with taskbar and live counter layout",
  imageFit: "contain",
});

await appendImageSlide({
  title: "DATA EXPORTS AND MANAGEMENT REPORTING",
  leftStatement: "Owners can move operational data into review and finance workflows without leaving the tenant workspace.",
  bullets: "◆  Export sales, products, inventory, customers, expenses and reports to CSV or PDF.\n\n◆  Date ranges, search and sorting keep exports reviewable.\n\n◆  Audit logs and payment reconciliation events preserve traceability.",
  imagePath: localAsset("flexpos-reports.png"),
  imageAlt: "FlexPOS reports and analytics screen",
});

// A dedicated full-desktop demo slide with an editable localhost browser bar.
{
  const source = deck.slides.getItem(5);
  const slide = source.duplicate();
  slide.moveTo(deck.slides.items.length - 2);
  const page = deck.slides.items.length - 1;
  const shapes = slide.shapes.items;
  shapes[2].text = "FLEXPOS · ENTERPRISE POS";
  shapes[3].text = String(page).padStart(2, "0");
  shapes[4].text = "FULL DESKTOP DEMO";
  shapes[5].text = "LOCALHOST BUILD";
  shapes[8].text = "◆  Full desktop view includes the navigation rail, POS workspace, current sale panel and taskbar.\n\n◆  Demo address: http://localhost:57724/\n\n◆  This capture reflects the running Flutter web build used for review.";
  const image = await replaceSlideImage(
    slide,
    desktopScreenshot,
    "Full FlexPOS desktop screenshot from the local web build",
    { left: 66, top: 181, width: 720, height: 396 },
    "contain",
  );
  // Keep the screenshot framed like a browser window and show the requested local URL.
  slide.shapes.add({
    geometry: "roundRect",
    name: "localhost-browser-bar",
    position: { left: 48, top: 142, width: 760, height: 32 },
    fill: "#E7E1DC",
    line: { style: "solid", fill: "#D9B7AA", width: 1 },
    borderRadius: "rounded-md",
  });
  const address = slide.shapes.add({
    geometry: "textbox",
    name: "localhost-address",
    position: { left: 66, top: 147, width: 720, height: 22 },
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  address.text = "localhost:57724/#/pos";
  address.text.style = { fontSize: 14, color: "#32191B", typeface: "Arial", alignment: "left" };
}

// A text-first status slide captures the remaining release and integration work without overstating completion.
{
  const source = deck.slides.getItem(8); // text-led two-column slide
  const slide = source.duplicate();
  slide.moveTo(deck.slides.items.length - 2);
  const page = deck.slides.items.length - 1;
  const shapes = slide.shapes.items;
  shapes[2].text = "FLEXPOS · ENTERPRISE POS";
  shapes[3].text = String(page).padStart(2, "0");
  shapes[4].text = "REMAINING RELEASE ITEMS";
  shapes[7].text = "Core online POS workflows are in place. Final release work focuses on evidence, signing and operator configuration.";
  shapes[7].text.style = { fontSize: 29, typeface: "Georgia", color: "#FFF9F6", bold: true, alignment: "left" };
  shapes[8].text = "◆  Physical scanner, printer and target-hardware checks.\n\n◆  Windows, iOS and macOS packaging, signing and smoke tests.\n\n◆  Production payment, SMTP and provider-event secrets.\n\n◆  Statutory tax, advanced accounting and deep industry depth remain roadmap items; offline stays intentionally excluded.";
}

// The existing Thank You slide is now last; update its page number to match the expanded deck.
const thankYou = deck.slides.getItem(deck.slides.items.length - 1);
for (const shape of thankYou.shapes.items) {
  if (String(shape.text) === "35") shape.text = String(deck.slides.items.length).padStart(2, "0");
}

const montage = await deck.export({ format: "webp", montage: true, scale: 1 });
await fs.writeFile(path.join(buildDir, "updated-deck-montage.webp"), new Uint8Array(await montage.arrayBuffer()));
const inspect = await deck.inspect({ kind: "slide,textbox,shape,image,notes,layout", maxChars: 120000 });
await fs.writeFile(path.join(buildDir, "updated-deck-inspect.ndjson"), inspect.ndjson ?? JSON.stringify(inspect));
const pptx = await PresentationFile.exportPptx(deck);
await pptx.save(candidatePath);
console.log(JSON.stringify({ candidatePath, finalPath, slideCount: deck.slides.items.length }));
