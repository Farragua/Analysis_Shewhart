# Analysis_Shewhart

Aplicación de análisis Shewhart que envía una notificación cuando una acción
cae dos sigmas o más.

- `Matlab/`: última versión de la aplicación desarrollada en MATLAB,
  recuperada del estado anterior a la migración.
- `Python/`: implementación actual en Python.

Los flujos de GitHub Actions ejecutan la versión Python:

```bash
pip install -r Python/requirements.txt
python Python/main_vYahoo.py
```
