// ===========================================================================
//  Diaries Club — generate-package-menu-pdf Edge Function (Module 2.7)
//
//  Composes a single-page A4 PDF for a birthday_packages row using
//  pdf-lib. Layout: header with package name + tier, hero photo, what's
//  included list, menu options summary, non-food offerings list, pricing
//  summary, contact footer.
//
//  Trigger: admin_package_regenerate_pdf RPC fires this via pg_net.
//  Auth: service-role bearer (verify_jwt=true). Updates
//  birthday_packages.pdf_url on success. Stored in package-pdfs bucket
//  (public per ARCHITECTURE-001).
// ===========================================================================

import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";
import { admin } from "./_shared/admin.ts";
import { requireServiceRole } from "./_shared/auth.ts";
import { audit } from "./_shared/audit.ts";
import {
  corsPreflight,
  errorResponse,
  jsonResponse,
} from "./_shared/response.ts";
import { captureException } from "./_shared/sentry.ts";

interface Req {
  package_id: string;
}

const NAVY = rgb(0.118, 0.227, 0.482); // #1E3A7B
const GOLD = rgb(0.961, 0.769, 0.259);
const GREY = rgb(0.4, 0.4, 0.4);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);
    const { package_id }: Req = await req.json();
    if (!package_id) {
      return jsonResponse(400, { ok: false, error: "missing_package_id" });
    }

    const { data: pkg, error } = await admin
      .from("birthday_packages")
      .select("*")
      .eq("id", package_id)
      .maybeSingle();
    if (error || !pkg) {
      return jsonResponse(404, { ok: false, error: "package_not_found" });
    }

    // ── Compose PDF ────────────────────────────────────────────────────────
    const doc = await PDFDocument.create();
    const page = doc.addPage([595, 842]); // A4 portrait
    const fontReg = await doc.embedFont(StandardFonts.Helvetica);
    const fontBold = await doc.embedFont(StandardFonts.HelveticaBold);

    let y = 800;

    page.drawText("DIARIES CLUB", {
      x: 50, y, size: 12, font: fontBold, color: GREY,
    });
    y -= 18;
    page.drawText("Birthday Package Menu", {
      x: 50, y, size: 10, font: fontReg, color: GREY,
    });
    y -= 30;

    // Title block
    page.drawText(pkg.name as string, {
      x: 50, y, size: 28, font: fontBold, color: NAVY,
    });
    y -= 24;
    const tierLabel = ((pkg.tier as string) ?? "")
      .replace(/_/g, " ")
      .replace(/\b\w/g, (c) => c.toUpperCase());
    page.drawText(tierLabel, {
      x: 50, y, size: 12, font: fontReg, color: GOLD,
    });
    y -= 30;

    // Description
    if (pkg.description) {
      const desc = wrapText(pkg.description as string, 80);
      for (const line of desc) {
        if (y < 80) break;
        page.drawText(line, {
          x: 50, y, size: 11, font: fontReg, color: rgb(0.2, 0.2, 0.2),
        });
        y -= 14;
      }
      y -= 10;
    }

    // Capacity / duration row
    const capLine = `${pkg.max_kids ?? 0} kids · ${pkg.max_adults ?? 0} adults · ${pkg.duration_hours ?? 0}hr party`;
    page.drawText(capLine, {
      x: 50, y, size: 11, font: fontBold, color: NAVY,
    });
    y -= 24;

    // What's included
    page.drawText("What's included", {
      x: 50, y, size: 14, font: fontBold, color: NAVY,
    });
    y -= 18;
    const inclusions = (pkg.inclusions as Record<string, unknown>) ?? {};
    if (Object.keys(inclusions).length === 0) {
      page.drawText("(Inclusions to be confirmed)", {
        x: 50, y, size: 10, font: fontReg, color: GREY,
      });
      y -= 14;
    } else {
      for (const [k, v] of Object.entries(inclusions)) {
        if (y < 80) break;
        const label = humanize(k);
        page.drawText(`• ${label}: ${String(v)}`, {
          x: 60, y, size: 10, font: fontReg, color: rgb(0.2, 0.2, 0.2),
        });
        y -= 14;
      }
    }
    y -= 10;

    // Menu options
    const menuOpts = (pkg.menu_options as Array<Record<string, unknown>>) ?? [];
    if (menuOpts.length > 0 && y > 200) {
      page.drawText("Menu options", {
        x: 50, y, size: 14, font: fontBold, color: NAVY,
      });
      y -= 18;
      for (const cat of menuOpts) {
        if (y < 80) break;
        page.drawText(String(cat.category ?? ""), {
          x: 50, y, size: 11, font: fontBold, color: rgb(0.2, 0.2, 0.2),
        });
        y -= 14;
        const opts = (cat.options as Array<Record<string, unknown>>) ?? [];
        for (const o of opts) {
          if (y < 80) break;
          const up = (o.upcharge_paise as number | undefined) ?? 0;
          const upLabel = up > 0 ? `  (+₹${up / 100})` : "";
          page.drawText(`  • ${o.name ?? ""}${upLabel}`, {
            x: 60, y, size: 10, font: fontReg, color: rgb(0.3, 0.3, 0.3),
          });
          y -= 12;
        }
      }
      y -= 10;
    }

    // Non-food offerings
    const nonFood =
      (pkg.non_food_offerings as Array<Record<string, unknown>>) ?? [];
    if (nonFood.length > 0 && y > 150) {
      page.drawText("Also included", {
        x: 50, y, size: 14, font: fontBold, color: NAVY,
      });
      y -= 18;
      for (const o of nonFood) {
        if (y < 80) break;
        const label = String(o.label ?? "");
        const detail = String(o.detail ?? "");
        page.drawText(`• ${label}${detail ? `: ${detail}` : ""}`, {
          x: 60, y, size: 10, font: fontReg, color: rgb(0.2, 0.2, 0.2),
        });
        y -= 14;
      }
      y -= 10;
    }

    // Pricing footer
    if (y > 100) {
      const price = (pkg.price_paise as number | undefined) ?? 0;
      const deposit = (pkg.deposit_paise as number | undefined) ?? 0;
      page.drawText(`Package price: ₹${price / 100}`, {
        x: 50, y, size: 14, font: fontBold, color: GOLD,
      });
      y -= 16;
      if (deposit > 0) {
        page.drawText(`Deposit to confirm: ₹${deposit / 100}`, {
          x: 50, y, size: 10, font: fontReg, color: GREY,
        });
        y -= 14;
      }
    }

    // Bottom contact line
    page.drawText("To book or ask questions, WhatsApp us via the app's birthday page.", {
      x: 50, y: 50, size: 9, font: fontReg, color: GREY,
    });

    const pdfBytes = await doc.save();

    // ── Upload + cache URL ─────────────────────────────────────────────────
    const fileName = `${package_id}.pdf`;
    const path = `packages/${fileName}`;
    const { error: upErr } = await admin.storage
      .from("package-pdfs")
      .uploadBinary(path, pdfBytes, {
        contentType: "application/pdf",
        upsert: true,
      });
    if (upErr) throw new Error(`storage_upload_failed: ${upErr.message}`);

    const { data: pub } = admin.storage
      .from("package-pdfs")
      .getPublicUrl(path);
    const pdfUrl = pub.publicUrl;

    await admin
      .from("birthday_packages")
      .update({ pdf_url: pdfUrl })
      .eq("id", package_id);

    await audit({
      action: "package.pdf.generated",
      entityType: "birthday_package",
      entityId: package_id,
      newValue: { pdf_url: pdfUrl, byte_size: pdfBytes.length },
    });

    return jsonResponse(200, {
      ok: true,
      package_id,
      pdf_url: pdfUrl,
    });
  } catch (e) {
    await captureException(e, { function: "generate-package-menu-pdf" });
    return errorResponse(e);
  }
});

function wrapText(text: string, charsPerLine: number): string[] {
  const words = text.split(/\s+/);
  const lines: string[] = [];
  let cur = "";
  for (const w of words) {
    if ((cur + " " + w).trim().length > charsPerLine) {
      if (cur) lines.push(cur);
      cur = w;
    } else {
      cur = cur ? `${cur} ${w}` : w;
    }
  }
  if (cur) lines.push(cur);
  return lines.slice(0, 6); // cap at 6 lines for the PDF
}

function humanize(slug: string): string {
  return slug
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}
