import { useMemo } from 'react';
import {
  createPlugin,
  discoveryApiRef,
  fetchApiRef,
  useApi,
} from '@backstage/core-plugin-api';

export const aapManagementPlugin = createPlugin({
  id: 'aap-management',
});

export function useAapManagementApi() {
  const discoveryApi = useApi(discoveryApiRef);
  const fetchApi = useApi(fetchApiRef);

  return useMemo(() => {
    const baseUrl = async () => {
      const url = await discoveryApi.getBaseUrl('aap-management');
      return url.replace(/\/+$/, '');
    };

    return {
      async listJobTemplates(params: {
        page: number;
        pageSize: number;
        search?: string;
        labels?: string;
      }) {
        const query = new URLSearchParams({
          page: String(params.page),
          page_size: String(params.pageSize),
        });
        if (params.search) {
          query.set('search', params.search);
        }
        if (params.labels) {
          query.set('labels', params.labels);
        }
        const response = await fetchApi.fetch(
          `${await baseUrl()}/job-templates?${query.toString()}`,
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
      async getSurveySpec(
        id: number,
        templateType: 'job_template' | 'workflow_job_template',
      ) {
        const query =
          templateType === 'workflow_job_template' ? '?type=workflow_job_template' : '';
        const response = await fetchApi.fetch(
          `${await baseUrl()}/job-templates/${id}/survey${query}`,
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
      async launchJobTemplate(
        id: number,
        templateType: 'job_template' | 'workflow_job_template',
        extraVars?: Record<string, unknown>,
      ) {
        const query =
          templateType === 'workflow_job_template' ? '?type=workflow_job_template' : '';
        const response = await fetchApi.fetch(
          `${await baseUrl()}/job-templates/${id}/launch${query}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(
              extraVars && Object.keys(extraVars).length > 0
                ? { extra_vars: extraVars }
                : {},
            ),
          },
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
      async listJobs(params: {
        page: number;
        pageSize: number;
        search?: string;
      }) {
        const query = new URLSearchParams({
          page: String(params.page),
          page_size: String(params.pageSize),
        });
        if (params.search) {
          query.set('search', params.search);
        }
        const response = await fetchApi.fetch(
          `${await baseUrl()}/jobs?${query.toString()}`,
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
      async getJob(id: number, jobType: 'job' | 'workflow_job' = 'job') {
        const query =
          jobType === 'workflow_job' ? '?type=workflow_job' : '';
        const response = await fetchApi.fetch(
          `${await baseUrl()}/jobs/${id}${query}`,
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
      async getJobStdout(id: number, jobType: 'job' | 'workflow_job' = 'job') {
        const query =
          jobType === 'workflow_job' ? '?type=workflow_job' : '';
        const response = await fetchApi.fetch(
          `${await baseUrl()}/jobs/${id}/stdout${query}`,
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
      async getJobEvents(
        id: number,
        jobType: 'job' | 'workflow_job' = 'job',
        params: { page?: number; pageSize?: number } = {},
      ) {
        const query = new URLSearchParams();
        if (jobType === 'workflow_job') {
          query.set('type', 'workflow_job');
        }
        if (params.page) {
          query.set('page', String(params.page));
        }
        if (params.pageSize) {
          query.set('page_size', String(params.pageSize));
        }
        const suffix = query.toString() ? `?${query.toString()}` : '';
        const response = await fetchApi.fetch(
          `${await baseUrl()}/jobs/${id}/events${suffix}`,
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
      async getJobTaskLogs(
        id: number,
        jobType: 'job' | 'workflow_job' = 'job',
      ) {
        const query =
          jobType === 'workflow_job' ? '?type=workflow_job' : '';
        const response = await fetchApi.fetch(
          `${await baseUrl()}/jobs/${id}/task-logs${query}`,
        );
        if (!response.ok) {
          throw new Error(await response.text());
        }
        return response.json();
      },
    };
  }, [discoveryApi, fetchApi]);
}
