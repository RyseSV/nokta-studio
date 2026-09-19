# Preferencias del proyecto Nokta

Este proyecto incluye Nokta Admin (`server/views/admin.html`), el servidor (`server/app.js`) y la app nativa (`native/NoktaStudio`).

## Revisión cruzada

Por solicitud del usuario, después de modificar código en este proyecto, solicitar una revisión del diff a un agente independiente antes de dar el trabajo por terminado. El revisor debe justificar sus hallazgos y examinar posibles regresiones. Corregir los problemas confirmados, realizar las verificaciones pertinentes y presentar al usuario los hallazgos, las razones y el resultado de la validación. Si no está disponible un revisor independiente, indicarlo explícitamente; no presentar una autorrevisión como revisión cruzada.

## Publicación y actualización autorizadas

El usuario solicita que cada cambio de código se entregue completo: después de las pruebas y la revisión cruzada, publicar los cambios pertinentes del servidor/Nokta Admin y actualizar las apps afectadas, sin volver a pedir permiso ni esperar otro mensaje para desplegar. Esta autorización incluye los commits y el push necesarios al repositorio de Nokta. No incluir cambios ajenos a la tarea ni secretos, dependencias o datos locales.

Verificar el resultado del despliegue y la instalación. Si una plataforma está bloqueada por conexión del dispositivo, firma o acceso, completar las demás y explicar el bloqueo concreto; no afirmar que una compilación equivale a una instalación o a un despliegue. La app nativa usa los esquemas NoktaStudio-macOS y NoktaStudio-iOS; el servidor está en https://nokta-studio.onrender.com y el remoto es RyseSV/nokta-studio. Confirmar los destinos y dispositivos disponibles antes de publicar.
