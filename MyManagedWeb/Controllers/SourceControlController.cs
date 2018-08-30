using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using System.Web.Http;
using System.Net.Http.Formatting;
using System.Net.Http.Headers;
using System.Web.Mvc;
using Microsoft.Azure.Common;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Auth;
using Microsoft.WindowsAzure.Storage.Queue;
using Newtonsoft.Json;
using System.Configuration;
using Microsoft.Azure.Services.AppAuthentication;
using Microsoft.Azure.KeyVault;

namespace MyManagedWeb.Controllers
{
    public class SourceControlController : ApiController
    {
        private static string vaultname = ConfigurationManager.AppSettings["KeyVault"];

        [System.Web.Http.HttpGet]
        [System.Web.Http.AllowAnonymous]
        [System.Web.Http.ActionName("Test")]
        [System.Web.Http.Route("api/SourceControl/Test")]
        public async Task<string> Test()
        {
            string t = await Task.Run(() => DateTime.UtcNow.ToLongTimeString());

            return t;
        }

        [System.Web.Http.HttpGet]
        [System.Web.Http.AllowAnonymous]
        [System.Web.Http.Route("api/SourceControl")]
        public async Task<HttpResponseMessage> Index(string TenantID, string Sub, string resourcegroup,string AppServiceName,string Repo, string Branch)
        {
            string StorageConnectionString = await GetSecret(vaultname, "ManagementStorage");
            var storageAccount = CloudStorageAccount.Parse(StorageConnectionString);

            var myMessage = new MyMessage
            {
                TenantId = TenantID,
                SubId = Sub,
                ResourceGroup = resourcegroup,
                AppServiceName = AppServiceName,
                Repo = Repo,
                Branch = Branch
            };
            var myMessageString = JsonConvert.SerializeObject(myMessage);

            var client = storageAccount.CreateCloudQueueClient();
            var queue = client.GetQueueReference("mymanagedapps");
            queue.CreateIfNotExists();
            var message = new CloudQueueMessage(myMessageString);
            queue.AddMessage(message);
            
            var template = @"{'$schema': 'https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#', 'contentVersion': '1.0.0.0', 'parameters': {}, 'variables': {}, 'resources': [],'outputs':{}}";
            template = template.Replace("'", "\"");

            HttpResponseMessage myResponse = new HttpResponseMessage { StatusCode = HttpStatusCode.OK };

            myResponse.Content = new StringContent(template, System.Text.Encoding.UTF8, "application/json");

            return myResponse;

        }

        internal static async Task<string> GetSecret(string vaultName, string nameKey)
        {


            string vaultUrl = $"https://{vaultName}.vault.azure.net/secrets/{nameKey}";

            AzureServiceTokenProvider azureServiceTokenProvider = new AzureServiceTokenProvider();

            var kv = new KeyVaultClient(new KeyVaultClient.AuthenticationCallback(azureServiceTokenProvider.KeyVaultTokenCallback));

            var secret = await kv.GetSecretAsync(vaultUrl).ConfigureAwait(false);

            var secretUri = secret.Value;

            return secretUri;
        }

    }

    internal class MyMessage
    {
        public string TenantId { get; set; }
        public string SubId { get; set; }
        public string ResourceGroup { get; set; }
        public string AppServiceName { get; set; }
        public string Repo { get; set; }
        public string Branch { get; set; }
    }
}
