# Para iniciar:

1. Ejecutar scripts

```
cd scripts
./generate_certs.sh
./deploy-model.sh
```

luego docker compose up -d

# Que falta:
- Inyectar el X-TenantID de Zitadel en los upstreams. (listo)
- Usar scopes de Zitadel para Coarse Grained con authz-casbin o openfga
- Hacer un Shared Auth Library con OpenFGA para mis microservicios, que pueda ejecutar la lógica de autorización.
- Implementar arquitectura que desacople autorización fina de lógica de negocio en Go para microservicios. (DDD optimizado)

# Para el modelo de authz necesito:
- Saber que puedo ver de un usuario por módulo, ej: **Why could user U perform an action A on an object O?**

Eg: Why user Rafa can create payroll for employee 123?

Because it's an HHRR manager in department ABC, which 

# Modelado:

## Conceptos:

Liquidación de sueldo = payslip / salary payment
finiquito puede significar dfespido o indemnización
liquidación también, pero puede no, entonces

employee_payment
employee_payment_item
employee_payment_concept

# Most important feature:
1. A user can create employee payments if is the hr manager of the employee's department
2. A user can read an employee payment if is the employee or the hr admin of the employee'sdepartment
3. A user can be a member of an organization
4. A department must have an organization that belongs to

# Types

User
EmployeePayment
Department
Organization


