import React from 'react';
import {
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  MenuItem,
  TextField,
  Typography,
} from '@material-ui/core';
import { Alert } from '@material-ui/lab';
import { useAapManagementApi } from '../plugin';
import { AapJobRef, AapJobTemplate, AapSurveyQuestion } from '../types';

type LaunchTemplateDialogProps = {
  template: AapJobTemplate | null;
  open: boolean;
  onClose: () => void;
  onLaunched: (job: AapJobRef) => void;
};

function initialValues(questions: AapSurveyQuestion[]) {
  return Object.fromEntries(
    questions.map(question => [
      question.variable,
      question.default !== undefined && question.default !== null
        ? String(question.default)
        : '',
    ]),
  );
}

function parseApiError(raw: unknown) {
  if (raw instanceof Error) {
    try {
      const parsed = JSON.parse(raw.message);
      if (parsed?.error?.message) {
        const nested = parsed.error.message.match(
          /AAP Controller \d+: (.+)$/s,
        );
        if (nested?.[1]) {
          try {
            const aapBody = JSON.parse(nested[1]);
            if (aapBody.variables_needed_to_start) {
              return `Missing required variables: ${aapBody.variables_needed_to_start.join(', ')}`;
            }
            return nested[1];
          } catch {
            return nested[1];
          }
        }
        return parsed.error.message;
      }
    } catch {
      // fall through
    }
    return raw.message;
  }
  return String(raw);
}

function launchedJobRef(
  template: AapJobTemplate,
  response: { id: number; type?: string },
): AapJobRef {
  const jobType =
    response.type === 'workflow_job' || template.templateType === 'workflow_job_template'
      ? 'workflow_job'
      : 'job';
  return { id: response.id, jobType };
}

export function LaunchTemplateDialog({
  template,
  open,
  onClose,
  onLaunched,
}: LaunchTemplateDialogProps) {
  const api = useAapManagementApi();
  const [loadingSurvey, setLoadingSurvey] = React.useState(false);
  const [launching, setLaunching] = React.useState(false);
  const [error, setError] = React.useState<string>();
  const [questions, setQuestions] = React.useState<AapSurveyQuestion[]>([]);
  const [values, setValues] = React.useState<Record<string, string>>({});

  React.useEffect(() => {
    if (!open || !template) {
      return;
    }

    let cancelled = false;
    setLoadingSurvey(true);
    setError(undefined);
    setQuestions([]);
    setValues({});

    (async () => {
      try {
        const survey = await api.getSurveySpec(template.id, template.templateType);
        if (cancelled) {
          return;
        }
        const spec = survey.spec ?? [];
        setQuestions(spec);
        setValues(initialValues(spec));

        if (spec.length === 0) {
          setLaunching(true);
          const launched = await api.launchJobTemplate(
            template.id,
            template.templateType,
          );
          if (!cancelled) {
            onLaunched(launchedJobRef(template, launched));
            onClose();
          }
        }
      } catch (e) {
        if (!cancelled) {
          setError(parseApiError(e));
        }
      } finally {
        if (!cancelled) {
          setLoadingSurvey(false);
          setLaunching(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [api, onClose, onLaunched, open, template]);

  const submit = async () => {
    if (!template) {
      return;
    }

    for (const question of questions) {
      if (question.required && !values[question.variable]?.trim()) {
        setError(`${question.question_name || question.variable} is required.`);
        return;
      }
    }

    setLaunching(true);
    setError(undefined);
    try {
      const extraVars = Object.fromEntries(
        questions.map(question => {
          const raw = values[question.variable] ?? '';
          if (question.type === 'integer') {
            return [question.variable, Number.parseInt(raw, 10)];
          }
          if (question.type === 'float') {
            return [question.variable, Number.parseFloat(raw)];
          }
          return [question.variable, raw];
        }),
      );
      const launched = await api.launchJobTemplate(
        template.id,
        template.templateType,
        extraVars,
      );
      onLaunched(launchedJobRef(template, launched));
      onClose();
    } catch (e) {
      setError(parseApiError(e));
    } finally {
      setLaunching(false);
    }
  };

  if (!template) {
    return null;
  }

  return (
    <Dialog fullWidth maxWidth="sm" open={open} onClose={onClose}>
      <DialogTitle>Launch {template.name}</DialogTitle>
      <DialogContent>
        {loadingSurvey && (
          <Typography variant="body2" color="textSecondary">
            Loading launch parameters…
          </Typography>
        )}
        {!loadingSurvey && questions.length === 0 && !error && launching && (
          <Typography variant="body2" color="textSecondary">
            Launching template…
          </Typography>
        )}
        {!loadingSurvey &&
          questions.map(question => {
            if (question.type === 'multiselect' || question.type === 'multiplechoice') {
              return (
                <TextField
                  key={question.variable}
                  select
                  fullWidth
                  margin="normal"
                  label={question.question_name || question.variable}
                  helperText={question.question_description}
                  value={values[question.variable] ?? ''}
                  required={question.required}
                  onChange={event =>
                    setValues(current => ({
                      ...current,
                      [question.variable]: event.target.value,
                    }))
                  }
                >
                  {(question.choices ?? []).map(choice => (
                    <MenuItem key={choice} value={choice}>
                      {choice}
                    </MenuItem>
                  ))}
                </TextField>
              );
            }

            return (
              <TextField
                key={question.variable}
                fullWidth
                margin="normal"
                label={question.question_name || question.variable}
                helperText={question.question_description}
                value={values[question.variable] ?? ''}
                required={question.required}
                multiline={question.type === 'textarea'}
                minRows={question.type === 'textarea' ? 3 : 1}
                type={question.type === 'password' ? 'password' : 'text'}
                onChange={event =>
                  setValues(current => ({
                    ...current,
                    [question.variable]: event.target.value,
                  }))
                }
              />
            );
          })}
        {error && (
          <Alert severity="error" style={{ marginTop: 16 }}>
            {error}
          </Alert>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={launching}>
          Cancel
        </Button>
        {questions.length > 0 && (
          <Button
            color="primary"
            variant="contained"
            disabled={loadingSurvey || launching}
            onClick={submit}
            startIcon={launching ? <CircularProgress size={16} /> : undefined}
          >
            Launch
          </Button>
        )}
      </DialogActions>
    </Dialog>
  );
}
