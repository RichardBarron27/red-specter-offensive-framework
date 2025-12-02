# 🔥 Red Specter Offensive Framework  
**Modular Offensive Security Toolkit for Ethical Hacking Labs & Authorized Penetration Testing**  
Version **1.4** • Created by **Richard B (Red Specter)**

---

## 🚩 Overview

**Red Specter** is a modular, menu-driven offensive security framework designed for:

- Ethical hacking labs  
- Red team training  
- Authorized penetration tests  
- Quick recon-to-report workflows  

It wraps core and advanced tooling in a clean workflow:

**Recon → Web Enumeration → Vulnerability Scanning → Exploitation → PrivEsc → Reporting**

Everything runs from a single launcher:

```bash
./redspecter.sh
⚡ Features
🧭 Core Modules
Module	Script	Description
Core Recon	core/redspecter-recon.sh	Host + domain recon, passive footprinting
Web Enumeration	core/redspecter-webenum.sh	HTTP probing, tech detection
Vulnerability Scanning	core/redspecter-vulnscan.sh	Nmap vuln scripts & baseline checks
