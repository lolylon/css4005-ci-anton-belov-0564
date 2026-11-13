#!/usr/bin/env python3
"""Render live CLI evidence text dumps into PNGs for REPORT.docx."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

EV = Path(__file__).resolve().parents[1] / "docs" / "evidence"


def fonts():
    try:
        return (
            ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 16),
            ImageFont.truetype(r"C:\Windows\Fonts\consolab.ttf", 18),
        )
    except OSError:
        d = ImageFont.load_default()
        return d, d


def render(txt_name: str, png_name: str, title: str) -> None:
    f, ftitle = fonts()
    p = EV / txt_name
    text = p.read_text(encoding="utf-8", errors="replace") if p.exists() else "(missing)"
    lines = text.splitlines() or [""]
    w, h = 1200, max(420, 60 + 22 * len(lines) + 40)
    img = Image.new("RGB", (w, h), (18, 18, 24))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 36], fill=(35, 55, 95))
    d.text((16, 8), f"ci-anton-belov-0564 | {title}", fill=(255, 255, 255), font=ftitle)
    y = 50
    for line in lines:
        d.text((16, y), line[:140], fill=(200, 220, 200), font=f)
        y += 22
        if y > h - 30:
            break
    out = EV / png_name
    img.save(out)
    print("wrote", out.name, out.stat().st_size)


def main() -> None:
    alb = (EV / "alb-https.txt").read_text(encoding="utf-8", errors="replace")
    tg = (EV / "alb-targets.txt").read_text(encoding="utf-8", errors="replace")
    (EV / "_alb_combo.txt").write_text("HTTPS probe\n" + alb + "\n\nTarget health\n" + tg, encoding="utf-8")

    pairs = [
        ("vpc-subnets.txt", "vpc-subnets.png", "VPC subnets"),
        ("sg-table.txt", "sg-table.png", "Security groups"),
        ("kubectl-all.txt", "kubectl-nodes.png", "kubectl get nodes/pods/hpa"),
        ("kubectl-all.txt", "kubectl-pods.png", "kubectl pods"),
        ("kubectl-all.txt", "kubectl-hpa.png", "kubectl hpa"),
        ("_alb_combo.txt", "alb-https.png", "ALB HTTPS + targets healthy"),
        ("alb-https.txt", "alb-readyz.png", "HTTPS /readyz"),
        ("alarms.txt", "alarms.png", "CloudWatch alarms"),
        ("budget.json", "budget.png", "AWS Budget $15"),
        ("mysql-status.txt", "mysql-replica-status.png", "MySQL status"),
        ("s3-listing.txt", "backup-s3.png", "S3 bucket listing"),
    ]
    for a, b, c in pairs:
        render(a, b, c)


if __name__ == "__main__":
    main()
