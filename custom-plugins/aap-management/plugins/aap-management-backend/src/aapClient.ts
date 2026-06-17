import { Config } from '@backstage/config';
import { InputError } from '@backstage/errors';
import { Agent, fetch as undiciFetch } from 'undici';

export type AapManagementConfig = {
  baseUrl: string;
  token?: string;
  username?: string;
  password?: string;
  checkSSL: boolean;
};

export function readAapManagementConfig(config: Config): AapManagementConfig {
  const section = config.getOptionalConfig('aapManagement');
  if (!section) {
    throw new InputError('Missing aapManagement configuration in app-config');
  }

  const baseUrl = section.getString('controllerUrl').replace(/\/+$/, '');
  const token = section.getOptionalString('token');
  const username = section.getOptionalString('username');
  const password = section.getOptionalString('password');
  const checkSSL = section.getOptionalBoolean('checkSSL') ?? true;

  if ((!token || token === 'changeme') && (!username || !password)) {
    throw new InputError(
      'aapManagement requires token or username/password in app-config',
    );
  }

  return {
    baseUrl,
    token: token && token !== 'changeme' ? token : undefined,
    username,
    password,
    checkSSL,
  };
}

export class AapControllerClient {
  constructor(private readonly cfg: AapManagementConfig) {}

  private dispatcher() {
    if (this.cfg.checkSSL) {
      return undefined;
    }
    return new Agent({ connect: { rejectUnauthorized: false } });
  }

  private authHeaders(): Record<string, string> {
    if (this.cfg.token) {
      return { Authorization: `Bearer ${this.cfg.token}` };
    }
    const encoded = Buffer.from(
      `${this.cfg.username}:${this.cfg.password}`,
    ).toString('base64');
    return { Authorization: `Basic ${encoded}` };
  }

  private apiUrl(path: string, query?: Record<string, string | number>) {
    const url = new URL(`${this.cfg.baseUrl}/api/controller/v2/${path}`);
    if (query) {
      Object.entries(query).forEach(([key, value]) => {
        if (value !== undefined && value !== '') {
          url.searchParams.set(key, String(value));
        }
      });
    }
    return url.toString();
  }

  async request<T>(
    path: string,
    query?: Record<string, string | number>,
    init?: { method?: string; body?: unknown },
  ): Promise<T> {
    const response = await undiciFetch(this.apiUrl(path, query), {
      method: init?.method ?? 'GET',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        ...this.authHeaders(),
      },
      body: init?.body ? JSON.stringify(init.body) : undefined,
      dispatcher: this.dispatcher(),
    });

    const text = await response.text();
    if (!response.ok) {
      throw new Error(
        `AAP Controller ${response.status}: ${text.slice(0, 400) || response.statusText}`,
      );
    }

    if (!text) {
      return {} as T;
    }
    return JSON.parse(text) as T;
  }

  async listJobTemplates(params: {
    page: number;
    pageSize: number;
    search?: string;
    labels?: string;
  }) {
    const query: Record<string, string | number> = {
      order_by: 'name',
      page_size: 100,
    };
    if (params.search) {
      query.search = params.search;
    }
    if (params.labels?.trim()) {
      query.labels__name__icontains = params.labels.trim();
    }

    const unified = await this.fetchAllPages<AapUnifiedJobTemplate>(
      'unified_job_templates/',
      query,
    );

    const launchable = unified
      .filter(
        template =>
          template.type === 'job_template' ||
          template.type === 'workflow_job_template',
      )
      .map(template => ({
        id: template.id,
        name: template.name,
        description: template.description,
        templateType: template.type as 'job_template' | 'workflow_job_template',
        summary_fields: template.summary_fields,
      }));

    const start = (params.page - 1) * params.pageSize;
    const end = start + params.pageSize;

    return {
      count: launchable.length,
      next: end < launchable.length ? String(params.page + 1) : null,
      previous: params.page > 1 ? String(params.page - 1) : null,
      results: launchable.slice(start, end),
    };
  }

  private async fetchAllPages<T>(
    path: string,
    query: Record<string, string | number>,
  ): Promise<T[]> {
    const results: T[] = [];
    let page = 1;

    while (true) {
      const data = await this.request<AapPagedResponse<T>>(path, {
        ...query,
        page,
      });
      results.push(...data.results);
      if (!data.next) {
        break;
      }
      page += 1;
      if (page > 50) {
        break;
      }
    }

    return results;
  }

  async getSurveySpec(id: number, templateType: AapTemplateType) {
    const basePath =
      templateType === 'workflow_job_template'
        ? `workflow_job_templates/${id}/survey_spec/`
        : `job_templates/${id}/survey_spec/`;
    return this.request<AapSurveySpec>(basePath);
  }

  async launchTemplate(
    id: number,
    templateType: AapTemplateType,
    extraVars?: Record<string, unknown>,
  ) {
    const path =
      templateType === 'workflow_job_template'
        ? `workflow_job_templates/${id}/launch/`
        : `job_templates/${id}/launch/`;
    const body: Record<string, unknown> = {};
    if (extraVars && Object.keys(extraVars).length > 0) {
      body.extra_vars = JSON.stringify(extraVars);
    }
    return this.request<AapJobLaunchResponse>(path, undefined, {
      method: 'POST',
      body,
    });
  }

  async launchJobTemplate(id: number) {
    return this.launchTemplate(id, 'job_template');
  }

  async listJobs(params: {
    page: number;
    pageSize: number;
    search?: string;
  }) {
    const query: Record<string, string | number> = {
      order_by: '-finished',
      page_size: 100,
    };
    if (params.search) {
      query.search = params.search;
    }

    const unified = await this.fetchAllPages<AapUnifiedJob>('unified_jobs/', query);
    const runs = unified.filter(
      job => job.type === 'job' || job.type === 'workflow_job',
    );

    const start = (params.page - 1) * params.pageSize;
    const end = start + params.pageSize;

    return {
      count: runs.length,
      next: end < runs.length ? String(params.page + 1) : null,
      previous: params.page > 1 ? String(params.page - 1) : null,
      results: runs.slice(start, end).map(job => ({
        id: job.id,
        name: job.name,
        status: job.status,
        failed: job.failed,
        started: job.started,
        finished: job.finished,
        elapsed: job.elapsed,
        jobType: job.type,
        summary_fields: job.summary_fields,
      })),
    };
  }

  private jobCollection(jobType: string) {
    return jobType === 'workflow_job' ? 'workflow_jobs' : 'jobs';
  }

  async getJob(id: number, jobType = 'job') {
    const collection = this.jobCollection(jobType);
    const job = await this.request<AapUnifiedJob & { playbook?: string }>(
      `${collection}/${id}/`,
    );

    let workflowNodes: AapWorkflowNode[] | undefined;
    if (jobType === 'workflow_job') {
      const nodes = await this.request<AapPagedResponse<AapWorkflowNode>>(
        `workflow_jobs/${id}/workflow_nodes/`,
        { page_size: 200, order_by: 'id' },
      );
      workflowNodes = nodes.results;
    }

    return {
      id: job.id,
      name: job.name,
      status: job.status,
      failed: job.failed,
      started: job.started,
      finished: job.finished,
      elapsed: job.elapsed,
      jobType,
      playbook: job.playbook,
      summary_fields: job.summary_fields,
      workflowNodes,
    };
  }

  async getJobStdout(id: number, jobType = 'job') {
    if (jobType === 'workflow_job') {
      return { content: '', note: 'Workflow jobs aggregate child jobs; see Events for progress.' };
    }

    const collection = this.jobCollection(jobType);
    const response = await this.request<{ content?: string }>(
      `${collection}/${id}/stdout/`,
    );
    return { content: response.content ?? '' };
  }

  private static readonly TASK_LOG_EVENTS = new Set([
    'runner_on_ok',
    'runner_on_failed',
    'runner_on_skipped',
    'runner_on_unreachable',
    'runner_on_start',
    'runner_on_item_ok',
    'runner_on_item_failed',
    'playbook_on_task_start',
  ]);

  private taskStatusFromEvent(eventName?: string) {
    if (!eventName) {
      return 'unknown';
    }
    if (eventName.includes('failed') || eventName.includes('unreachable')) {
      return eventName.includes('unreachable') ? 'unreachable' : 'failed';
    }
    if (eventName.includes('skipped')) {
      return 'skipped';
    }
    if (eventName.includes('_start')) {
      return 'started';
    }
    if (eventName.includes('_ok')) {
      return 'ok';
    }
    return 'unknown';
  }

  private extractEventStdout(event: AapJobEvent) {
    if (event.stdout?.trim()) {
      return event.stdout.trim();
    }

    const res = event.event_data?.res;
    if (!res) {
      return '';
    }

    if (typeof res.stdout === 'string' && res.stdout.trim()) {
      return res.stdout.trim();
    }
    if (typeof res.msg === 'string' && res.msg.trim()) {
      return res.msg.trim();
    }
    if (Array.isArray(res.results)) {
      return res.results
        .map(item => {
          if (typeof item?.stdout === 'string' && item.stdout.trim()) {
            return item.stdout.trim();
          }
          if (typeof item?.msg === 'string' && item.msg.trim()) {
            return item.msg.trim();
          }
          return '';
        })
        .filter(Boolean)
        .join('\n');
    }

    return '';
  }

  private mapJobEventToTaskLog(event: AapJobEvent, workflowNode?: string) {
    return {
      id: event.id,
      counter: event.counter,
      created: event.created,
      event: event.event,
      status: this.taskStatusFromEvent(event.event),
      task: event.event_data?.task ?? event.event_data?.play ?? '',
      host:
        event.event_data?.host ??
        event.event_data?.remote_addr ??
        event.event_data?.res?.host ??
        '',
      play: event.event_data?.play,
      stdout: this.extractEventStdout(event),
      workflowNode,
    };
  }

  private async fetchTaskLogsForJob(jobId: number, workflowNode?: string) {
    const events = await this.fetchAllPages<AapJobEvent>(
      `jobs/${jobId}/job_events/`,
      { page_size: 200, order_by: 'counter' },
    );

    return events
      .filter(
        event =>
          event.event && AapControllerClient.TASK_LOG_EVENTS.has(event.event),
      )
      .map(event => this.mapJobEventToTaskLog(event, workflowNode));
  }

  async getJobTaskLogs(id: number, jobType = 'job') {
    if (jobType === 'workflow_job') {
      const nodes = await this.request<AapPagedResponse<AapWorkflowNode>>(
        `workflow_jobs/${id}/workflow_nodes/`,
        { page_size: 200, order_by: 'id' },
      );

      const logs: ReturnType<AapControllerClient['mapJobEventToTaskLog']>[] =
        [];
      for (const node of nodes.results) {
        const childJob = node.summary_fields?.job;
        if (!childJob?.id) {
          continue;
        }
        if (childJob.type && childJob.type !== 'job') {
          continue;
        }
        const nodeName =
          childJob.name ?? node.unified_job_name ?? `Node ${node.id}`;
        const childLogs = await this.fetchTaskLogsForJob(
          childJob.id,
          nodeName,
        );
        logs.push(...childLogs);
      }

      return {
        count: logs.length,
        next: null,
        previous: null,
        results: logs,
      };
    }

    const results = await this.fetchTaskLogsForJob(id);
    return {
      count: results.length,
      next: null,
      previous: null,
      results,
    };
  }

  async getJobEvents(
    id: number,
    jobType = 'job',
    params: { page?: number; pageSize?: number } = {},
  ) {
    const page = params.page ?? 1;
    const pageSize = params.pageSize ?? 50;

    if (jobType === 'workflow_job') {
      const nodes = await this.request<AapPagedResponse<AapWorkflowNode>>(
        `workflow_jobs/${id}/workflow_nodes/`,
        { page_size: 200, order_by: 'id' },
      );
      const results = nodes.results.map((node, index) => ({
        id: node.id,
        counter: index + 1,
        created: undefined,
        event: 'workflow_node',
        stdout: node.summary_fields?.job?.status,
        eventData: undefined,
        hostName: undefined,
        task: node.summary_fields?.job?.name ?? node.unified_job_name,
        play: node.summary_fields?.job?.type,
      }));
      const start = (page - 1) * pageSize;
      return {
        count: results.length,
        next: start + pageSize < results.length ? String(page + 1) : null,
        previous: page > 1 ? String(page - 1) : null,
        results: results.slice(start, start + pageSize),
      };
    }

    const collection = this.jobCollection(jobType);
    const data = await this.request<AapPagedResponse<AapJobEvent>>(
      `${collection}/${id}/job_events/`,
      { page, page_size: pageSize, order_by: 'counter' },
    );

    return {
      count: data.count,
      next: data.next,
      previous: data.previous,
      results: data.results.map(event => ({
        id: event.id,
        counter: event.counter,
        created: event.created,
        event: event.event,
        stdout: this.extractEventStdout(event),
        eventData: event.event_data,
        hostName:
          event.event_data?.host ??
          event.event_data?.remote_addr ??
          event.event_data?.res?.host ??
          undefined,
        task: event.event_data?.task ?? event.event_data?.play ?? undefined,
        play: event.event_data?.play ?? undefined,
      })),
    };
  }
}

export type AapPagedResponse<T> = {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
};

export type AapLabel = {
  id: number;
  name: string;
  description?: string;
};

export type AapTemplateType = 'job_template' | 'workflow_job_template';

export type AapJobTemplate = {
  id: number;
  name: string;
  description?: string;
  templateType: AapTemplateType;
  summary_fields?: {
    organization?: { name?: string };
    inventory?: { name?: string };
    project?: { name?: string };
    labels?: { count?: number; results?: AapLabel[] };
    recent_jobs?: Array<{
      id: number;
      status: string;
      finished?: string;
    }>;
  };
};

export type AapUnifiedJobTemplate = {
  id: number;
  type: string;
  name: string;
  description?: string;
  summary_fields?: AapJobTemplate['summary_fields'];
};

export type AapUnifiedJob = {
  id: number;
  type: string;
  name: string;
  status: string;
  failed: boolean;
  started?: string | null;
  finished?: string | null;
  elapsed?: number;
  summary_fields?: AapJob['summary_fields'];
};

export type AapSurveyQuestion = {
  variable: string;
  type: string;
  required?: boolean;
  default?: string | number | boolean;
  question_name: string;
  question_description?: string;
  choices?: string[];
  min?: number;
  max?: number;
};

export type AapSurveySpec = {
  name?: string;
  description?: string;
  spec: AapSurveyQuestion[];
};

export type AapJobLaunchResponse = {
  id: number;
  status: string;
  type: string;
  url: string;
};

export type AapJob = {
  id: number;
  name: string;
  status: string;
  failed: boolean;
  started?: string | null;
  finished?: string | null;
  elapsed?: number;
  summary_fields?: {
    job_template?: { id?: number; name?: string };
    unified_job_template?: { id?: number; name?: string };
    organization?: { name?: string };
    created_by?: { username?: string };
  };
};

export type AapWorkflowNode = {
  id: number;
  unified_job_name?: string;
  do_not_run?: boolean;
  success_nodes?: number[];
  failure_nodes?: number[];
  always_nodes?: number[];
  summary_fields?: {
    job?: { id?: number; name?: string; status?: string; type?: string };
  };
};

export type AapJobEvent = {
  id: number;
  counter?: number;
  created?: string;
  event?: string;
  stdout?: string;
  event_data?: {
    host?: string;
    remote_addr?: string;
    task?: string;
    play?: string;
    res?: {
      host?: string;
      stdout?: string;
      msg?: string;
      results?: Array<{ stdout?: string; msg?: string }>;
    };
  };
};
