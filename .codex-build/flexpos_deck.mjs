import fs from 'node:fs/promises';
import path from 'node:path';
import { Presentation, PresentationFile } from 'file:///C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';

const workspaceDir = process.cwd();
const buildDir = path.join(workspaceDir, '.codex-build');
const previewDir = path.join(buildDir, 'previews');
const outputDir = path.join(workspaceDir, 'presentation_output');
const finalPptx = path.join(outputDir, 'FlexPOS_35_slide_presentation.pptx');

const CREAM = '#F5ECE5';
const MAROON = '#4B0C0D';
const MAROON_DARK = '#310709';
const INK = '#32191B';
const MUTED = '#76575A';
const SOFT = '#D9B7AA';
const WHITE = '#FFF9F6';
const FONT_SERIF = 'Georgia';
const FONT_SANS = 'Arial';

const logoPath = path.join(workspaceDir, 'assets', 'branding', 'flexpos_logo.png');
const assetDir = path.join(workspaceDir, 'presentation_assets');

async function readArrayBuffer(filePath) {
  const bytes = await fs.readFile(filePath);
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

async function writeBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

function addShape(slide, geometry, position, fill = 'none', lineFill = 'none', lineWidth = 0, extra = {}) {
  return slide.shapes.add({
    geometry,
    position,
    fill,
    line: { style: 'solid', fill: lineFill, width: lineWidth },
    ...extra,
  });
}

function addText(slide, text, position, style = {}, extra = {}) {
  const shape = addShape(slide, 'textbox', position, 'none', 'none', 0, extra);
  shape.text = text;
  shape.text.style = {
    typeface: FONT_SANS,
    fontSize: 20,
    color: INK,
    alignment: 'left',
    verticalAlignment: 'middle',
    ...style,
  };
  return shape;
}

function addImage(slide, imageBytes, position, alt, fit = 'contain') {
  return slide.images.add({
    blob: imageBytes,
    contentType: 'image/png',
    alt,
    fit,
    position,
  });
}

function addBase(slide, pageNo, section = 'FLEXPOS · ENTERPRISE POS') {
  slide.background.fill = CREAM;
  addShape(slide, 'rect', { left: 0, top: 0, width: 1280, height: 14 }, MAROON);
  addShape(slide, 'rect', { left: 0, top: 706, width: 1280, height: 14 }, MAROON);
  addText(slide, section, { left: 930, top: 24, width: 280, height: 24 }, {
    fontSize: 11,
    typeface: FONT_SANS,
    bold: true,
    color: MUTED,
    alignment: 'right',
  });
  addText(slide, String(pageNo).padStart(2, '0'), { left: 1195, top: 666, width: 44, height: 22 }, {
    fontSize: 12,
    typeface: FONT_SERIF,
    color: MUTED,
    alignment: 'right',
  });
}

function addTitle(slide, title, subtitle = '') {
  addText(slide, title.toUpperCase(), { left: 54, top: 44, width: 740, height: 64 }, {
    fontSize: 32,
    typeface: FONT_SERIF,
    bold: true,
    color: INK,
  });
  if (subtitle) {
    addText(slide, subtitle, { left: 850, top: 56, width: 330, height: 36 }, {
      fontSize: 11,
      typeface: FONT_SANS,
      bold: true,
      color: MUTED,
      alignment: 'right',
    });
  }
  addShape(slide, 'rect', { left: 54, top: 112, width: 170, height: 5 }, SOFT);
}

function addBullets(slide, bullets, position, color = MUTED, size = 19) {
  const text = bullets.map((item) => `◆  ${item}`).join('\n');
  return addText(slide, text, position, {
    fontSize: size,
    typeface: FONT_SANS,
    color,
    bold: false,
    verticalAlignment: 'top',
  });
}

function addScreenshotSlide(slide, pageNo, title, imageBytes, bullets, caption = 'SCREEN OVERVIEW') {
  addBase(slide, pageNo);
  addTitle(slide, title, caption);
  addShape(slide, 'roundRect', { left: 48, top: 142, width: 760, height: 485 }, WHITE, SOFT, 1, { borderRadius: 'rounded-lg' });
  addImage(slide, imageBytes, { left: 60, top: 154, width: 736, height: 461 }, `${title} screenshot`, 'contain');
  addBullets(slide, bullets, { left: 860, top: 176, width: 330, height: 380 }, MUTED, 18);
}

function addTextSlide(slide, pageNo, title, body, bullets = [], accent = MAROON) {
  addBase(slide, pageNo);
  addTitle(slide, title);
  addShape(slide, 'rect', { left: 48, top: 142, width: 414, height: 480 }, accent);
  addText(slide, body, { left: 76, top: 178, width: 350, height: 290 }, {
    typeface: FONT_SERIF,
    fontSize: 28,
    color: WHITE,
    bold: true,
    verticalAlignment: 'top',
  });
  if (bullets.length) addBullets(slide, bullets, { left: 535, top: 182, width: 630, height: 320 }, MUTED, 21);
  addShape(slide, 'rect', { left: 535, top: 540, width: 170, height: 4 }, SOFT);
}

async function main() {
  await fs.mkdir(previewDir, { recursive: true });
  await fs.mkdir(outputDir, { recursive: true });
  const [logoBytes, login, dashboard, pos, products, inventory, orders, modules, reports, customers, accounting] = await Promise.all([
    readArrayBuffer(logoPath),
    readArrayBuffer(path.join(assetDir, 'flexpos-login.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-dashboard.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-pos.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-products.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-inventory.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-orders.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-modules.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-reports.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-customers.png')),
    readArrayBuffer(path.join(assetDir, 'flexpos-accounting.png')),
  ]);

  const presentation = Presentation.create({ slideSize: { width: 1280, height: 720 } });

  // 01 — cover
  {
    const slide = presentation.slides.add();
    slide.background.fill = MAROON_DARK;
    addShape(slide, 'rect', { left: 0, top: 0, width: 650, height: 720 }, CREAM);
    addShape(slide, 'rect', { left: 650, top: 0, width: 630, height: 720 }, MAROON_DARK);
    addImage(slide, logoBytes, { left: 112, top: 92, width: 430, height: 240 }, 'FlexPOS logo', 'contain');
    addText(slide, 'FlexPOS', { left: 84, top: 360, width: 490, height: 74 }, { typeface: FONT_SERIF, fontSize: 54, bold: true, color: INK });
    addText(slide, 'Enterprise point-of-sale\nand business management', { left: 84, top: 444, width: 500, height: 100 }, { typeface: FONT_SERIF, fontSize: 26, color: INK, verticalAlignment: 'top' });
    addText(slide, 'PRODUCT PRESENTATION', { left: 770, top: 132, width: 350, height: 30 }, { fontSize: 14, bold: true, color: SOFT, alignment: 'center' });
    addText(slide, 'One secure workspace\nfor every branch', { left: 735, top: 218, width: 440, height: 170 }, { typeface: FONT_SERIF, fontSize: 42, bold: true, color: WHITE, alignment: 'center', verticalAlignment: 'top' });
    addText(slide, 'Prepared for FlexPOS · 2026', { left: 760, top: 568, width: 390, height: 28 }, { fontSize: 15, color: SOFT, alignment: 'center' });
    addText(slide, '01', { left: 1180, top: 665, width: 44, height: 24 }, { typeface: FONT_SERIF, fontSize: 12, color: SOFT, alignment: 'right' });
  }

  addTextSlide(presentation.slides.add(), 2, 'Project Introduction',
    'FlexPOS brings checkout, inventory, purchasing, accounting and analytics into one tenant-aware workspace.',
    ['Built for branch-based operations and fast cashier workflows.', 'Server-enforced money and stock movements with Supabase RLS.', 'Responsive interface for desktop and smaller screens.']);

  addScreenshotSlide(presentation.slides.add(), 3, 'Login and Splash Experience', login,
    ['Branded loading screen with a short 0–100% progress sequence.', 'Email and password authentication through Supabase Auth.', 'Responsive sign-in surface with recovery and account creation paths.']);

  addTextSlide(presentation.slides.add(), 4, 'Register and Account Recovery',
    'Authentication covers the full entry journey before a user reaches a business workspace.',
    ['Create an account with email verification.', 'Resend verification and request password recovery.', 'Update password through the PKCE recovery flow.'], MAROON);

  addScreenshotSlide(presentation.slides.add(), 5, 'Dashboard', dashboard,
    ['Business snapshot with net sales, gross profit, customer dues and expenses.', 'Role, branch, currency and timezone context stays visible.', 'Quick actions open the most common operational workflows.']);

  addScreenshotSlide(presentation.slides.add(), 6, 'Point of Sale', pos,
    ['Search by product, SKU or barcode and add items to the current sale.', 'Warehouse, register shift and customer context stay in the checkout panel.', 'Cart totals, taxes, discounts and completion actions remain visible.']);

  addScreenshotSlide(presentation.slides.add(), 7, 'Product Catalog', products,
    ['Search, sorting, pagination and bulk selection across active SKUs.', 'Product images, SKU, barcode, price and stock state appear together.', 'Catalog actions support variants, pricing and stock tracking.']);

  addScreenshotSlide(presentation.slides.add(), 8, 'Inventory', inventory,
    ['Available quantities are shown per tracked SKU and warehouse.', 'Stocktake, damage, transfer and adjustment actions are accessible at the top.', 'Images keep the physical product easy to identify during operations.']);

  addTextSlide(presentation.slides.add(), 9, 'Stock Adjustments and Transfers',
    'Inventory movements stay auditable from the warehouse to the stock ledger.',
    ['Record wastage, damage and manual corrections with a reason.', 'Transfer quantities between warehouses and branches.', 'Use stocktake workflows to reconcile physical counts.']);

  addScreenshotSlide(presentation.slides.add(), 10, 'Orders and Receipts', orders,
    ['Recent sales are searchable by invoice number and date.', 'Status filters separate paid, pending, refunded and cancelled orders.', 'Receipt, tax invoice, returns and exchanges are available from each order.']);

  addTextSlide(presentation.slides.add(), 11, 'Returns and Exchange',
    'Post-sale workflows keep the original sale traceable while correcting stock and payment outcomes.',
    ['Return selected items or quantities from an invoice.', 'Exchange items with a clear value difference.', 'Keep return reasons and downstream ledger entries auditable.']);

  addScreenshotSlide(presentation.slides.add(), 12, 'Customers', customers,
    ['Customer records include contact details, groups and credit context.', 'Search works across name, code, phone and email.', 'Customer selection flows directly into POS checkout and ledger views.']);

  addTextSlide(presentation.slides.add(), 13, 'CRM and Customer Relationships',
    'CRM workflows extend the customer record beyond the point of sale.',
    ['Track leads, opportunities and follow-ups in one tenant.', 'Keep notes, reminders and quotations tied to the right customer.', 'Use role-based access for customer data and activity.']);

  addTextSlide(presentation.slides.add(), 14, 'Suppliers and Purchasing',
    'Purchasing connects supplier records to the products and stock they replenish.',
    ['Manage supplier contacts, terms and purchasing history.', 'Create requisitions and purchase orders by branch or warehouse.', 'Keep supplier lists searchable with shared data controls.']);

  addTextSlide(presentation.slides.add(), 15, 'Purchase Orders and Goods Receipts',
    'Inbound stock becomes a controlled, reviewable business process.',
    ['Receive ordered quantities against a purchase order.', 'Capture costs, taxes and discrepancies before stock is posted.', 'Use goods receipts to maintain a reliable inventory trail.']);

  addScreenshotSlide(presentation.slides.add(), 16, 'Feature Modules', modules,
    ['Customers, CRM, suppliers, expenses, accounting and reports are grouped by operational purpose.', 'Shared navigation keeps the workspace predictable across modules.', 'Each module follows tenant-aware permissions and data access.']);

  addTextSlide(presentation.slides.add(), 17, 'Payment Options',
    'Checkout supports the payment paths used by FlexPOS without cluttering the cashier workflow.',
    ['Cash records an immediate tendered payment.', 'UPI shows a bill-specific QR and requires a success or failed confirmation.', 'Razorpay opens the real provider checkout in test mode.']);

  addTextSlide(presentation.slides.add(), 18, 'UPI Checkout',
    'The cashier can present the exact bill amount through the configured UPI address.',
    ['UPI ID: kaushal.pithva@ptaxis.', 'QR payload includes the bill value before checkout is finalized.', 'Success records the payment; Failed leaves the sale unfinalized.'], MAROON);

  addTextSlide(presentation.slides.add(), 19, 'Razorpay Test Checkout',
    'Razorpay uses the provider order and signature verification flow rather than a placeholder QR.',
    ['The client requests a server-created Razorpay order.', 'Checkout opens in test mode with provider callbacks.', 'Server verification records the final payment state.']);

  addTextSlide(presentation.slides.add(), 20, 'Receipts and Tax Invoices',
    'Every completed sale can produce a compact receipt or a tax-ready invoice.',
    ['Small receipt output fits thermal printer widths.', 'Tax invoice includes line items, tax splits and business context.', 'Print and export flows are kept separate from sale completion.']);

  addTextSlide(presentation.slides.add(), 21, 'Authentication and Tenants',
    'A user signs in once and works inside the business context assigned by membership.',
    ['Business, branch and membership relationships stay explicit.', 'RLS policies scope reads and writes to the active tenant.', 'The removed Orange Hotel tenant no longer appears in the workspace.']);

  addTextSlide(presentation.slides.add(), 22, 'Roles and Permissions',
    'FlexPOS separates what a user can see from what they can do.',
    ['System roles cover administration, cashier, inventory and accounting work.', 'Memberships connect users to a business and role.', 'Permission checks protect sensitive operations and management screens.']);

  addTextSlide(presentation.slides.add(), 23, 'Branches and Registers',
    'The same tenant model supports multiple operational locations.',
    ['Branches carry timezone, contact and active-state configuration.', 'Registers and shifts reconcile cash activity by location.', 'Warehouse and register context follow the active branch.']);

  addTextSlide(presentation.slides.add(), 24, 'Customer Credit and Ledger',
    'Credit is treated as a ledger-backed balance rather than an informal note.',
    ['Customer dues surface on dashboards and reports.', 'Receipts and repayments update the ledger.', 'Credit limits remain visible when selecting a customer in POS.']);

  addTextSlide(presentation.slides.add(), 25, 'Expenses',
    'Operating expenses stay connected to the business and reporting period.',
    ['Record expense categories, payees and amounts.', 'Attach notes and supporting context where needed.', 'Expense totals flow into management reporting.']);

  addScreenshotSlide(presentation.slides.add(), 26, 'Accounting and Tax', accounting,
    ['Chart of accounts, fiscal year and cash/bank tools share one control surface.', 'Trial balance and GST summary are available from the accounting module.', 'Operational entries and recurring expenses can be posted from the same screen.']);

  addScreenshotSlide(presentation.slides.add(), 27, 'Reports and Analytics', reports,
    ['Net sales, expenses, customer dues and gross profit are available by period.', 'Reports support 7-day, 30-day, 90-day and custom ranges.', 'CSV, Excel and PDF export actions keep reporting portable.']);

  addTextSlide(presentation.slides.add(), 28, 'Audit Logs and Governance',
    'Operational actions leave a trace that helps owners review changes.',
    ['Tenant-scoped audit logs record important business operations.', 'Sensitive actions require the relevant permission.', 'History supports reconciliation, review and incident follow-up.']);

  addTextSlide(presentation.slides.add(), 29, 'Hardware and Scanning',
    'FlexPOS keeps hardware workflows online and explicit for a reliable counter experience.',
    ['Camera and keyboard barcode input find products quickly.', 'Printer and device bridges expose capability and heartbeat state.', 'Physical scanner validation remains a deployment check for each device.']);

  addTextSlide(presentation.slides.add(), 30, 'Online-only Operations',
    'The product intentionally keeps the source of truth online instead of introducing an offline queue.',
    ['Checkout, stock and payments require an authenticated connection.', 'No deferred offline sales or background sync are enabled.', 'Connectivity and authorization failures surface to the operator.'], MAROON);

  addTextSlide(presentation.slides.add(), 31, 'Engineering Quality',
    'Production readiness is supported by a shared design system and repeatable checks.',
    ['Responsive Material 3 surfaces keep desktop and mobile layouts aligned.', 'Structured logs redact passwords, tokens and provider secrets.', 'Analyzer, unit and integration checks protect core workflows.']);

  addTextSlide(presentation.slides.add(), 32, 'Testing and Production Verification',
    'The release workflow validates the paths that move money and stock.',
    ['Auth, products, sales, returns and purchasing have integration coverage.', 'Payment verification checks provider status and signatures.', 'Concurrent sessions and hardware checks remain explicit release evidence.']);

  addTextSlide(presentation.slides.add(), 33, 'Deployment and Release Readiness',
    'FlexPOS can ship as a web or mobile application with environment-specific configuration.',
    ['Supabase project configuration is supplied through environment files.', 'Razorpay secrets stay server-side in Edge Functions.', 'Signing, packaging and production smoke tests are part of the release checklist.']);

  addTextSlide(presentation.slides.add(), 34, 'Security and RLS',
    'Tenant isolation is enforced at the database boundary, not only in the client.',
    ['Public tables use row-level security with business-aware predicates.', 'Service-role secrets never enter the Flutter client.', 'Business deletion was scoped by exact tenant ID and verified afterward.']);

  // 35 — end
  {
    const slide = presentation.slides.add();
    slide.background.fill = MAROON_DARK;
    addShape(slide, 'rect', { left: 0, top: 0, width: 1280, height: 720 }, MAROON_DARK);
    addImage(slide, logoBytes, { left: 480, top: 112, width: 320, height: 180 }, 'FlexPOS logo', 'contain');
    addText(slide, 'Thank You', { left: 250, top: 330, width: 780, height: 90 }, { typeface: FONT_SERIF, fontSize: 58, bold: true, color: WHITE, alignment: 'center' });
    addText(slide, 'FlexPOS · Enterprise POS and business management', { left: 300, top: 440, width: 680, height: 36 }, { fontSize: 18, color: SOFT, alignment: 'center' });
    addText(slide, '35', { left: 1180, top: 665, width: 44, height: 24 }, { typeface: FONT_SERIF, fontSize: 12, color: SOFT, alignment: 'right' });
  }

  for (const [index, slide] of presentation.slides.items.entries()) {
    const stem = `slide-${String(index + 1).padStart(2, '0')}`;
    await writeBlob(path.join(previewDir, `${stem}.png`), await presentation.export({ slide, format: 'png', scale: 1 }));
  }
  const pptx = await PresentationFile.exportPptx(presentation);
  await pptx.save(path.join(buildDir, 'FlexPOS_35_slide_presentation.draft.pptx'));
  console.log(JSON.stringify({ finalPptx, slides: presentation.slides.items.length, previewDir }));
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
