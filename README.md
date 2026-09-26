# tf-exp

Laboratorio de Terraform con CI/CD en GitHub Actions. Gestiona dos parámetros de AWS SSM en dos entornos (dev y prod) con state remoto en S3, autenticación a AWS por OIDC (sin llaves) y aprobación manual para producción.

El objetivo no es la infraestructura en sí, sino el flujo: cómo un cambio viaja de un PR a dev y luego a prod de forma segura y revisable.

## Qué gestiona

| Entorno | Parámetros SSM | State (S3) |
|---|---|---|
| dev | `/exp/a`, `/exp/b` | `exp/terraform.tfstate` |
| prod | `/prod/exp/a`, `/prod/exp/b` | `prod/exp/terraform.tfstate` |

Bucket del state: `tfstate-ruben-20260923` (versionado, cifrado, sin acceso público). Región: `us-east-1`.

## Estructura

```
.
├── main.tf               # provider, variable param_prefix y los dos aws_ssm_parameter
├── backend.tf            # backend s3 parcial: region, use_lockfile, encrypt
├── dev.s3.tfbackend      # bucket y key del state de dev
├── prod.s3.tfbackend     # bucket y key del state de prod
├── prod.tfvars           # param_prefix = "/prod/exp"
└── .github/workflows/
    ├── terraform-plan.yml    # plan en cada PR, comentado en el PR
    ├── terraform-apply.yml   # apply en dev y luego en prod al mergear a main
    ├── oidc-test.yml         # prueba manual: asumir el rol de dev y ejecutar sts get-caller-identity
    ├── prueba-escape.yml     # prueba manual: intentar asumir el rol de prod sin environment (debe fallar)
    └── concurrency-test.yml  # prueba manual: ver cómo se encolan ejecuciones con concurrency
```

## Decisiones de diseño

**Backend con configuración parcial.** El bloque `backend "s3"` no admite variables, así que `backend.tf` solo tiene lo común (región, locking y cifrado) y el bucket y la key llegan con `-backend-config`. El pipeline elige `dev.s3.tfbackend` o `prod.s3.tfbackend` según el job, no una persona.

**Locking nativo en S3.** `use_lockfile = true` crea un `.tflock` junto al state con escritura condicional. No hace falta tabla DynamoDB.

**Un state por entorno.** dev y prod nunca comparten state, así un error en dev no puede tocar recursos de prod.

**OIDC sin llaves.** GitHub Actions pide un token OIDC y lo cambia por credenciales temporales con `aws-actions/configure-aws-credentials`. No hay access keys guardadas en el repo ni en secrets.

**Un rol por entorno.**
- `github-tf-exp-dev`: puede leer y escribir el state `exp/*` y los parámetros `/exp/*`.
- `github-tf-exp-prod`: puede leer y escribir el state `prod/exp/*` y los parámetros `/prod/exp/*`. Su trust policy exige el `sub` exacto del environment `production`, así que solo un job con `environment: production` puede asumirlo. `prueba-escape.yml` demuestra que sin environment el rol se rechaza.

Los ARN de los roles se leen de las variables del repo `AWS_ROLE_DEV` y `AWS_ROLE_PROD`. Los roles y el OIDC provider se crean en un proyecto Terraform aparte (`tf-lab/ci-iam`), no en este repo.

## Flujo del pipeline

```
PR a main
  └─ terraform-plan: fmt -check, init (dev), validate, plan, comentario en el PR

merge a main (branch protection)
  └─ terraform-apply
       ├─ apply-dev:  init (dev), plan -out, apply del plan guardado
       └─ apply-prod: espera aprobación del environment "production",
                      init (prod), plan -var-file=prod.tfvars -out, apply
```

**Concurrency.**
- Plan: un grupo por PR con `cancel-in-progress: true`. Un push nuevo cancela el plan viejo, porque solo interesa el último.
- Apply: un solo grupo con `cancel-in-progress: false`. Nunca se cancela un apply a medias; las ejecuciones se encolan.

**-lock-timeout.** El plan usa `-lock-timeout=3m` para esperar el lock en lugar de fallar de inmediato si otro proceso lo tiene.

## Cómo trabajar en este repo

Todo cambio va por PR. Solo el CI aplica.

1. Crea una rama, modifica el código y abre un PR a `main`.
2. Revisa el plan comentado en el PR, en especial cualquier `destroy` o reemplazo (`-/+`).
3. Mergea. El apply de dev corre solo.
4. Aprueba el environment `production` en GitHub para aplicar en prod.

### Ejecutar en local (solo lectura)

```powershell
terraform init -reconfigure -backend-config="dev.s3.tfbackend"
terraform plan
```

Para prod:

```powershell
terraform init -reconfigure -backend-config="prod.s3.tfbackend"
terraform plan -var-file="prod.tfvars"
```

Usa `-reconfigure` al cambiar de entorno, no `-migrate-state`: migrar copiaría el state de un entorno al otro.

## Limitaciones conocidas

- **Se aprueba prod sin ver su plan.** El plan comentado en el PR es el de dev. El de prod se calcula después de la aprobación. La mejora es separar `plan-prod` (guarda el plan como artifact y lo muestra) de `apply-prod` (aprueba y aplica ese plan exacto).
- **El apply no usa `-lock-timeout`**, solo el plan del PR. Si un apply coincide con un plan en curso, el apply falla en lugar de esperar.
- **`state_bucket` en `backend.tf` no se usa.** El bucket viene de los archivos `.tfbackend`.
- Los workflows `oidc-test`, `prueba-escape` y `concurrency-test` son de aprendizaje y se lanzan a mano (`workflow_dispatch`).

## Requisitos

- Terraform 1.16.2
- Provider `hashicorp/aws ~> 6.0`
- Cuenta AWS con el bucket del state, el OIDC provider de GitHub y los dos roles ya creados
