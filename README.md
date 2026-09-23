# BenyControl

MVP nativo iOS para cargadores BENY compatibles con Z-BOX, usando UDP unicast y sin descubrimiento broadcast.

## Estado

Implementa la primera iteración: configuración manual, PIN en Keychain, consulta de modelo/valores/estado, inicio, parada, límite de corriente y registro de diagnóstico redactado. El protocolo está portado de `Jarauvi/beny_wifi`; los paquetes se envían como texto ASCII hexadecimal por UDP, no como bytes binarios Modbus.

## Generar y abrir el proyecto

En un Mac con Xcode 16 o posterior:

1. Instala XcodeGen (`brew install xcodegen`) si no lo tienes.
2. En esta carpeta ejecuta `xcodegen generate`.
3. Abre `BenyControl.xcodeproj` en Xcode y ejecuta los tests del esquema `BenyControlTests`.

El destino es iOS 16. El proyecto solicita únicamente el permiso de red local. No usa Bonjour, multicast ni broadcast.

## Uso

Introduce la IP, puerto UDP, serie y PIN local del cargador en Settings. El número de serie no viaja en las solicitudes unicast de este MVP; se conserva como identificador de configuración y para una futura validación visual. El PIN sí se codifica en cada datagrama, se guarda en Keychain y se redacta en el diagnóstico.

Para acceso remoto, la VPN debe enrutar tanto la IP del cargador como el tráfico UDP al puerto configurado. No expongas UDP/3333 a Internet.

## Límites conocidos

La compilación y ejecución en iPhone requieren macOS/Xcode; este entorno Windows no dispone de las herramientas de Apple, por lo que no ha sido posible compilar aquí. Los tests incluidos no necesitan un cargador físico.
