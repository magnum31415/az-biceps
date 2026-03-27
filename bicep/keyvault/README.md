# Qué se ha desplegado (Bicep)

## 1. Key Vault

Recurso principal para almacenamiento seguro de:

- Secrets
- Keys
- Certificates

---

## 2. RBAC sobre el Key Vault

Se asignan permisos a un grupo de Entra ID:

- BI-azKeyVault-Officer

Roles asignados:

- Key Vault Secrets Officer
- Key Vault Crypto Officer
- Key Vault Certificates Officer
- Key Vault Contributor

Resultado:

- El grupo tiene acceso amplio al Key Vault

---

## 3. Grupo en Entra ID

Creado externamente (fuera de Bicep, vía script):

- Tipo: Security Group
- Usado para asignaciones RBAC

Importante:

- No pertenece al Resource Group
- Vive en Microsoft Entra ID (identity plane)

---

## 4. Action Group (Azure Monitor)

Sistema de notificación:

- Configuración de email
- Usado por las alertas

---

## 5. Activity Log Alert

Alerta de seguridad que detecta:

- Eliminación de Key Vault

Evento monitorizado:

- Microsoft.KeyVault/vaults/delete

Comportamiento:

- Se dispara al eliminar un Key Vault
- Envía notificación por email

Scope:

- Nivel subscription
- Filtrado por Resource Group

---

## 6. Monitoring (Log Analytics + Diagnostic Settings)

### Log Analytics Workspace

- Almacena logs y métricas
- Retención configurada (ej: 30 días)

### Diagnostic Settings

- Conecta el Key Vault con Log Analytics

Logs capturados:

- AuditEvent
- Métricas (AllMetrics)

---

## Arquitectura resultante

Key Vault  
↓  
RBAC (grupo Entra ID)  
↓  
Diagnostic Settings → Log Analytics  
↓  
Activity Log Alert → Action Group → Email  

---

## Consideraciones importantes

### Eliminación (destroy)

- Key Vault → eliminado
- Alerts → eliminadas
- Log Analytics → eliminado
- Grupo Entra ID → NO eliminado

---

### Coste

| Componente        | Coste |
|------------------|------|
| Key Vault        | Bajo |
| Log Analytics    | Sí (según uso) |
| Alerts           | Gratis |
| RBAC             | Gratis |

---

### Seguridad

- Uso de RBAC en lugar de access policies
- Roles asignados amplios (mejorable con least privilege)

---

## Conclusión

El despliegue incluye:

- Infraestructura (Key Vault)
- Control de acceso (RBAC)
- Monitorización (Log Analytics)
- Alertas (Activity Log)
- Notificaciones (Action Group)

Esto representa un setup base alineado con buenas prácticas de Azure (CAF / WAF).
