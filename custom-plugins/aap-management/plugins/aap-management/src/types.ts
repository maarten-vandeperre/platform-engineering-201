export type AapPagedResponse<T> = {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
};

export type AapSurveyQuestion = {
  variable: string;
  type: string;
  required?: boolean;
  default?: string | number | boolean;
  question_name: string;
  question_description?: string;
  choices?: string[];
};

export type AapSurveySpec = {
  name?: string;
  description?: string;
  spec: AapSurveyQuestion[];
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
    labels?: {
      count?: number;
      results?: Array<{ id: number; name: string; description?: string }>;
    };
    recent_jobs?: Array<{ id: number; status: string; finished?: string }>;
  };
};

export type AapJob = {
  id: number;
  name: string;
  status: string;
  failed: boolean;
  started?: string | null;
  finished?: string | null;
  elapsed?: number;
  jobType?: 'job' | 'workflow_job' | string;
  playbook?: string;
  summary_fields?: {
    job_template?: { id?: number; name?: string };
    unified_job_template?: { id?: number; name?: string };
    organization?: { name?: string };
    created_by?: { username?: string };
  };
  workflowNodes?: AapWorkflowNode[];
};

export type AapWorkflowNode = {
  id: number;
  unified_job_name?: string;
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
  hostName?: string;
  task?: string;
  play?: string;
};

export type AapJobTaskLog = {
  id: number;
  counter?: number;
  created?: string;
  event?: string;
  status: string;
  task?: string;
  host?: string;
  play?: string;
  stdout?: string;
  workflowNode?: string;
};

export type AapJobStdout = {
  content: string;
  note?: string;
};

export type AapJobRef = {
  id: number;
  jobType: 'job' | 'workflow_job';
};
