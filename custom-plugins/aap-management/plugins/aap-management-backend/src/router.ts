import {
  HttpAuthService,
  LoggerService,
  RootConfigService,
} from '@backstage/backend-plugin-api';
import { InputError } from '@backstage/errors';
import express, { Request } from 'express';
import Router from 'express-promise-router';
import {
  AapControllerClient,
  readAapManagementConfig,
} from './aapClient';

export interface RouterOptions {
  logger: LoggerService;
  config: RootConfigService;
  httpAuth: HttpAuthService;
}

function parsePositiveInt(value: unknown, fallback: number, max: number) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return fallback;
  }
  return Math.min(Math.floor(parsed), max);
}

export async function createRouter(
  options: RouterOptions,
): Promise<express.Handler> {
  const { logger, config, httpAuth } = options;
  const aapConfig = readAapManagementConfig(config);
  const client = new AapControllerClient(aapConfig);
  const router = Router();
  router.use(express.json());

  const requireUser = async (request: Request) => {
    await httpAuth.credentials(request, { allow: ['user'] });
  };

  router.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  router.get('/job-templates', async (req, res) => {
    await requireUser(req);
    const page = parsePositiveInt(req.query.page, 1, 1000);
    const pageSize = parsePositiveInt(req.query.page_size, 10, 100);
    const search = typeof req.query.search === 'string' ? req.query.search : '';
    const labels = typeof req.query.labels === 'string' ? req.query.labels : '';

    try {
      const data = await client.listJobTemplates({
        page,
        pageSize,
        search,
        labels,
      });
      res.json(data);
    } catch (error) {
      logger.error(String(error));
      throw new InputError(
        `Failed to list job templates: ${error instanceof Error ? error.message : error}`,
      );
    }
  });

  router.get('/job-templates/:id/survey', async (req, res) => {
    await requireUser(req);
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) {
      throw new InputError('Invalid job template id');
    }
    const templateType =
      req.query.type === 'workflow_job_template'
        ? 'workflow_job_template'
        : 'job_template';

    try {
      const survey = await client.getSurveySpec(id, templateType);
      res.json(survey);
    } catch (error) {
      logger.error(String(error));
      throw new InputError(
        `Failed to load template survey: ${error instanceof Error ? error.message : error}`,
      );
    }
  });

  router.post('/job-templates/:id/launch', async (req, res) => {
    await requireUser(req);
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) {
      throw new InputError('Invalid job template id');
    }
    const templateType =
      req.query.type === 'workflow_job_template'
        ? 'workflow_job_template'
        : 'job_template';
    const extraVars =
      req.body &&
      typeof req.body === 'object' &&
      req.body.extra_vars &&
      typeof req.body.extra_vars === 'object' &&
      !Array.isArray(req.body.extra_vars)
        ? (req.body.extra_vars as Record<string, unknown>)
        : undefined;

    try {
      const job = await client.launchTemplate(id, templateType, extraVars);
      res.status(202).json(job);
    } catch (error) {
      logger.error(String(error));
      throw new InputError(
        `Failed to launch template: ${error instanceof Error ? error.message : error}`,
      );
    }
  });

  router.get('/jobs', async (req, res) => {
    await requireUser(req);
    const page = parsePositiveInt(req.query.page, 1, 1000);
    const pageSize = parsePositiveInt(req.query.page_size, 10, 100);
    const search = typeof req.query.search === 'string' ? req.query.search : '';

    try {
      const data = await client.listJobs({ page, pageSize, search });
      res.json(data);
    } catch (error) {
      logger.error(String(error));
      throw new InputError(
        `Failed to list jobs: ${error instanceof Error ? error.message : error}`,
      );
    }
  });

  return router;
}
