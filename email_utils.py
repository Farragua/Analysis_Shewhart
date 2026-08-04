"""Envío de correo vía SMTP de Gmail (réplica 1:1 del bloque sendmail de los .m).

Los dos mains (diario y semanal) comparten esta lógica: credenciales desde
variables de entorno, SMTP smtp.gmail.com:587 con STARTTLS (TLSv1.2) y envío
individual a cada destinatario.
"""

import os
import smtplib
import ssl
from email.header import Header
from email.mime.text import MIMEText


def enviar_reporte(asunto, msg_final):
    # 1. Extraer credenciales
    mail_remitente = os.environ.get('EMAIL_USER', '')
    password_envio = os.environ.get('EMAIL_PASS', '')

    if not mail_remitente or not password_envio:
        raise RuntimeError('Las credenciales de correo desde los Secrets de GitHub llegaron VACÍAS a Python.')

    # Forzar a que sean cadenas de texto limpias (elimina espacios invisibles)
    mail_remitente = mail_remitente.strip()
    password_envio = password_envio.strip()

    # 2. Lista de destinatarios
    lista_correos = [
        mail_remitente,  # Usa la variable del remitente directamente
        'pozo.dionisio@gmail.com',
        'gustems.maestre@gmail.com',
    ]

    # 3-4. Servidor SMTP de Gmail + TLS (TLSv1.2)
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2

    # 5. Enviar el correo uno a uno
    for destino_actual in lista_correos:
        destino_actual = destino_actual.strip()
        try:
            msg_email = MIMEText(msg_final, 'plain', 'utf-8')
            msg_email['Subject'] = Header(asunto, 'utf-8')
            msg_email['From'] = mail_remitente
            msg_email['To'] = destino_actual
            with smtplib.SMTP('smtp.gmail.com', 587) as server:
                server.ehlo()
                server.starttls(context=context)
                server.ehlo()
                server.login(mail_remitente, password_envio)
                server.sendmail(mail_remitente, [destino_actual], msg_email.as_string())
            print(f'✉️ Correo enviado con éxito a: {destino_actual}')
        except Exception as ME:
            print(f'Warning: ❌ Error al enviar a {destino_actual}: {ME}')
